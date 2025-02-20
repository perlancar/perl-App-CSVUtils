package App::CSVUtils::csv_dump;

use 5.010001;
use strict;
use warnings;

# AUTHORITY
# DATE
# DIST
# VERSION

use App::CSVUtils qw(gen_csv_util);

gen_csv_util(
    name => 'csv_dump',
    summary => 'Dump CSV as data structure (array of array/hash)',
    description => <<'MARKDOWN',

This utility reads CSV file then dumps it as a text table, or as JSON if you
specify the `--format=json` or `--json` option.

MARKDOWN

    add_args => {
        hash => {
            summary => 'Dump CSV as array of hashrefs instead of array of arrayrefs',
            schema => 'true*',
            cmdline_aliases => {H=>{}},
        },
    },
    tags => ['category:converting', 'outputs-data-structure'],

    examples => [
        {
            summary => 'Convert CSV to a text table',
            argv => ['file.csv'],
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'Convert CSV to JSON',
            src => '[[prog]] file.csv --json',
            src_plang => 'bash',
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],

    on_input_header_row => sub {
        my $r = shift;

        # this is a key we add ourselves
        $r->{output_rows} //= [];

        if ($r->{util_args}{hash}) {
            $r->{wants_input_row_as_hashref} = 1;
        } else {
            push @{ $r->{output_rows} }, $r->{input_row};
        }
    },

    on_input_data_row => sub {
        my $r = shift;
        push @{ $r->{output_rows} },
            $r->{util_args}{hash} ? $r->{input_row_as_hashref} : $r->{input_row};
    },

    writes_csv => 0,

    on_end => sub {
        my $r = shift;
        $r->{result} = [200, "OK", $r->{output_rows}];
    },
);

1;
# ABSTRACT:
