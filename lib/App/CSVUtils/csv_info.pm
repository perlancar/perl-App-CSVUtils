package App::CSVUtils::csv_info;

use 5.010001;
use strict;
use warnings;

# AUTHORITY
# DATE
# DIST
# VERSION

use App::CSVUtils qw(gen_csv_util);

gen_csv_util(
    name => 'csv_info',
    summary => 'Dump CSV as data structure (array of array/hash)',
    description => <<'_',

This utility reads CSV file then dumps it as a text table, or as JSON if you
specify the `--format=json` or `--json` option.

_

    add_args => {
        hash => {
            summary => 'Dump CSV as array of hashrefs instead of array of arrayrefs',
            schema => 'true*',
            cmdline_aliases => {H=>{}},
        },
    },

    writes_csv => 0,

    after_close_input_files => sub {
        my $r = shift;

        $r->{result} = [200, "OK", {
            field_count => scalar @{$r->{input_fields}},
            fields      => $r->{input_fields},

            row_count        => $r->{input_header_row_count} + $r->{input_data_row_count},
            header_row_count => $r->{input_header_row_count},
            data_row_count   => $r->{input_data_row_count},

            # XXX this is incorrect, we have set encoding to utf-8 so handle
            # position != number of bytes
            #file_size   => (-s $r->{input_fh}),
        }];
    }
);

1;
# ABSTRACT:
