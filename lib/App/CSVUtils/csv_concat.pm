package App::CSVUtils::csv_concat;

use 5.010001;
use strict;
use warnings;

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
        $r->{has_collected_fields} //= 0; # to mark the first vs second loop over input files
    },

    after_close_input_files => sub {
        my $r = shift;
        unless ($r->{has_collected_fields}++) {
            # we just finished the first loop over input files to gather the
            # field names, repeat once to gather the data rows now
            $r->{wants_repeat_files}++;
        }
    },

    on_input_header_row => sub {
        my $r = shift;

        unless ($r->{has_collected_fields}) {
            $r->{output_fields} //= [];
            $r->{output_fields_idx} //= {};
            for my $j (0 .. $#{ $r->{input_fields} }) {
                my $field = $r->{input_fields}[$j];
                unless (grep {$field eq $_} @{ $r->{output_fields} }) {
                    push @{ $r->{output_fields} }, $field;
                    $r->{output_fields_idx}{$field} = $#{ $r->{output_fields} };
                }
            }
            # in the first loop over input files, we only read the header to
            # collect the fields.
            $r->{wants_skip_file}++;
        }
    },

    on_input_data_row => sub {
        my $r = shift;

        if ($r->{has_collected_fields}) {
            my $combined_row = [("") x @{ $r->{output_fields} }];
            for my $j (0 .. $#{ $r->{input_fields} }) {
                my $field = $r->{input_fields}[$j];
                $combined_row->[ $r->{output_fields_idx}{$field} ] = $r->{input_row}[$j];
            }
            $r->{code_print_row}->($combined_row);
        }
    },
);

1;
# ABSTRACT:

=head1 IMPLEMENTATION NOTES

We loop the files twice. The first time, we gather all the field names by
reading the header rows and do not bother reading the data rows. The second
time, we collect the data rows.
