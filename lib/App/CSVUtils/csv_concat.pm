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
    description => <<'_',

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

_
    add_args => {
        %App::CSVUtils::argspecopt_with_data_rows,
    },

    reads_multiple_csv => 1,

    before_open_input_files => sub {
        my $r = shift;

        # we add the following keys to the stash
        $r->{all_input_fields} = [];
        $r->{all_input_fh} = [];
    },

    on_input_header_row => sub {
        my $r = shift;

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

        # print all the data rows
        my $csv = $r->{input_parser};
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
    },
);

1;
# ABSTRACT:

=head1 IMPLEMENTATION NOTES

We first read only the header rows for all input files, while collecting the
input filehandles. Then we read the data rows of all the files ourselves.
