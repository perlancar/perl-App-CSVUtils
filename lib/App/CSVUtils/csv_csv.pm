package App::CSVUtils::csv_csv;

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
    name => 'csv_csv',
    summary => 'Convert CSV to CSV',
    description => <<'MARKDOWN',

Why convert CSV to CSV? When you want to change separator/quote/escape
character, for one. Or you want to remove header or add one.

Example:

    # in.csv
    name,age
    andi,12
    budi,13

    % csv-csv in.csv --output-sep-char ';'
    name;age
    andi;12
    budi;13

MARKDOWN
    add_args => {
    },
    tags => ['category:converting','category:munging'],

    on_input_data_row => sub {
        my $r = shift;

        $r->{code_print_row}->($r->{input_row});
    },
);

1;
# ABSTRACT:
