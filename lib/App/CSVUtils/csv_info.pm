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
    summary => 'Show information about CSV file (number of rows, fields, etc)',
    description => <<'_',


_

    add_args => {
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
