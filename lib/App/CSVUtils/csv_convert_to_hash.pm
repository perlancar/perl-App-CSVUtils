package App::CSVUtils::csv_convert_to_hash;

use 5.010001;
use strict;
use warnings;

# AUTHORITY
# DATE
# DIST
# VERSION

use App::CSVUtils qw(gen_csv_util);

gen_csv_util(
    name => 'csv_convert_to_hash',
    summary => 'Return a hash of field names as keys and first data row as values',
    description => <<'_',

_

    add_args => {
        rownum => {
            schema => 'posint*',
            default => 1,
            summary => 'Row number (e.g. 1 for first data row)',
            pos => 1,
        },
    },
    examples => [
        {
            summary => 'Create a table containing field name as keys and second row as values',
            argv => ['file.csv', 2],
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],

    on_begin => sub {
        my $r = shift;

        # check arguments & set defaults
        $r->{util_args}{rownum} //= 1;
    },

    on_input_header_row => sub {
        my $r = shift;

        $r->{result} = [200, "OK", { map { $_ => undef } @{ $r->{input_fields} } }];
    },

    on_input_data_row => sub {
        my $r = shift;

        if ($r->{input_data_rownum} == $r->{util_args}{rownum}) {
            $r->{result} = [200, "OK", { map { $_ => $r->{input_row}[ $r->{input_fields_idx}{$_} ] } @{ $r->{input_fields} } }];
            $r->{wants_skip_file}++;
        }
    },

    writes_csv => 0,
);

1;
# ABSTRACT:
