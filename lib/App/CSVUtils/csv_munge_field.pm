package App::CSVUtils::csv_munge_field;

use 5.010001;
use strict;
use warnings;

# AUTHORITY
# DATE
# DIST
# VERSION

use App::CSVUtils qw(
                        gen_csv_util
                        compile_eval_code
                );

gen_csv_util(
    name => 'csv_munge_field',
    summary => 'Munge a field in every row of CSV file with Perl code',
    description => <<'_',

Perl code (-e) will be called for each row (excluding the header row) and `$_`
will contain the value of the field, and the Perl code is expected to modify it.
`$main::row` will contain the current row array. `$main::rownum` contains the
row number (2 means the first data row). `$main::csv` is the <pm:Text::CSV_XS>
object. `$main::fields_idx` is also available for additional information.

To munge multiple fields, use <prog:csv-munge-row>.

_
    add_args => {
        %App::CSVUtils::argspec_field_1,
        %App::CSVUtils::argspec_eval_2,
    },

    examples => [
        {
            summary => 'Square a number field in CSV',
            argv => ['file.csv', 'num', '$_ = $_*$_'],
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],

    on_input_header_row => sub {
        my $r = shift;

        # check that selected field exists in the header
        my $field_idx = $r->{input_fields_idx}{ $r->{util_args}{field} };
        die [404, "Field '$r->{util_args}{field}' not found in CSV"]
            unless defined $field_idx;

        # we add the following keys to the stash
        $r->{code} = compile_eval_code($r->{util_args}{eval}, 'eval');
        $r->{field_idx} = $field_idx;
    },

    on_input_data_row => sub {
        my $r = shift;

        {
            local $_ = $r->{input_row}[ $r->{field_idx} ];
            local $main::row = $r->{input_row};
            local $main::rownum = $r->{input_rownum};
            local $main::csv = $r->{input_parser};
            local $main::fields_idx = $r->{input_fields_idx};
            eval { $r->{code}->() };
            die [500, "Error while munging row ".
                 "#$r->{input_rownum} field '$r->{util_args}{field}' value '$_': $@\n"] if $@;
            $r->{input_row}->[ $r->{field_idx} ] = $_;
        }
        $r->{code_print_row}->($r->{input_row});
    },
);

1;
# ABSTRACT:
