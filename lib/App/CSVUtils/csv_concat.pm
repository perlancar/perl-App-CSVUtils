package App::CSVUtils::csv_concat;

use 5.010001;
use strict;
use warnings;
use Log::ger;

# AUTHORITY
# DATE
# DIST
# VERSION

use App::CSVUtils qw(
                        gen_csv_util
                );

gen_csv_util(
    name => 'csv_concat',
    summary => 'Concatenate several CSV files together, '.
        'collecting all the fields',
    description => <<'MARKDOWN',

Example, concatenating this CSV:

    col1,col2
    1,2
    3,4

and:

    col2,col4
    a,b
    c,d
    e,f

and:

    col3
    X
    Y

will result in:

    col1,col2,col4,col3
    1,2,
    3,4,
    ,a,b
    ,c,d
    ,e,f
    ,,,X
    ,,,Y

When `--overlay` option is enabled, the result will be:

    col1,col2,col4,col3
    1,2,b,X
    3,4,d,Y
    ,e,f,

When `--overlay` as well as `--overwrite-fields` option are enabled, the result
will be:

    col1,col2,col4,col3
    1,a,b,X
    3,c,d,Y
    ,e,f,

Keywords: join, merge, overlay

MARKDOWN
    add_args => {
        overlay => {
            summary => 'Whether to overlay rows from second and subsequent CSV files to the first',
            schema => 'bool*',
            description => <<'MARKDOWN',

By default, rows from the second CSV file will be added after all the rows from
the first CSV are added, and so on. However, when this option is enabled, the
rows the second and subsequent CSV files will be added together (overlaid). See
the utility's example for an illustration.

See also the `--overwrite-fields` option.

MARKDOWN
        },
        overwrite_fields => {
            summary => 'Whether fields from subsequent CSV files should overwrite existing fields from previous CSV files',
            schema => 'bool*',
            description => <<'MARKDOWN',

When in overlay mode (`--overlay`), by default the value for a field is
retrieved from the first CSV file that has the field. With `--overwrite-fields`
option enabled, the value will be retrieved from the last CSV that has the
field. See the utility's example for an illustration.

MARKDOWN
        },
    },
    tags => ['category:combining', 'join', 'merge'],

    reads_multiple_csv => 1,

    before_open_input_files => sub {
        my $r = shift;

        # we add the following keys to the stash
        $r->{all_input_fields} = [];
        $r->{all_input_fh} = [];
    },

    on_input_header_row => sub {
        my $r = shift;

        # after we read the header row of each input file, we record the fields
        # as well as the filehandle, so we can resume reading the data rows
        # later. before printing all the rows, we collect all the fields from
        # all files first.

        push @{ $r->{all_input_fields} }, $r->{input_fields};
        push @{ $r->{all_input_fh} }, $r->{input_fh};
        $r->{wants_skip_file}++;
    },

    after_close_input_files => sub {
        my $r = shift;

        # collect all output fields
        $r->{output_fields} = [];
        $r->{output_fields_idx} = {};
        for my $i (0 .. $#{ $r->{all_input_fields} }) {
            my $input_fields = $r->{all_input_fields}[$i];
            for my $j (0 .. $#{ $input_fields }) {
                my $field = $input_fields->[$j];
                unless (grep {$field eq $_} @{ $r->{output_fields} }) {
                    push @{ $r->{output_fields} }, $field;
                    $r->{output_fields_idx}{$field} = $#{ $r->{output_fields} };
                }
            }
        }

        my $csv = $r->{input_parser};

        if ($r->{util_args}{overlay}) {

            my $overwrite_fields = $r->{util_args}{overwrite_fields};
            my $output_fields_idx = $r->{output_fields_idx};
            while (1) {
                my $has_not_eof;
                my $combined_row = [("") x @{ $r->{output_fields} }];
                my %seen_fields;
                for my $i (0 .. $#{ $r->{all_input_fh} }) {
                    my $fh = $r->{all_input_fh}[$i];

                    next if eof($fh);
                    $has_not_eof++;
                    my $row = $csv->getline($fh);
                    my $input_fields = $r->{all_input_fields}[$i];
                    for my $j (0 .. $#{ $input_fields }) {
                        my $field = $input_fields->[$j];
                        if (!($seen_fields{$field}++) || $overwrite_fields) {
                            $combined_row->[ $output_fields_idx->{$field} ] = $row->[$j];
                        }
                    }
                } # for all_input_fh
                last unless $has_not_eof;
                $r->{code_print_row}->($combined_row);
            } # while 1

        } else {

            # print all the data rows
            for my $i (0 .. $#{ $r->{all_input_fh} }) {
                log_trace "[%d/%d] Adding rows from file #%d ...",
                    $i+1, scalar(@{$r->{all_input_fh}}), $i+1;
                my $fh = $r->{all_input_fh}[$i];
                my $input_fields = $r->{all_input_fields}[$i];
                while (my $row = $csv->getline($fh)) {
                    my $combined_row = [("") x @{ $r->{output_fields} }];
                    for my $j (0 .. $#{ $input_fields }) {
                        my $field = $input_fields->[$j];
                        $combined_row->[ $r->{output_fields_idx}{$field} ] = $row->[$j];
                    }
                    $r->{code_print_row}->($combined_row);
                }
            } # for all input fh

        }
    },
);

1;
# ABSTRACT:

=head1 IMPLEMENTATION NOTES

We first read only the header rows for all input files, while collecting the
input filehandles. Then we read the data rows of all the files ourselves.
