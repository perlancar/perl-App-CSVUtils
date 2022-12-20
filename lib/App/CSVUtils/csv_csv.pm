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
    description => <<'_',

Why convert CSV to CSV? When you want to change separator/quote/escape
character, for one. Or you want to remove header or add one.

_
    add_args => {
    },

    on_input_data_row => sub {
        my $r = shift;

        $r->{code_printrow}->($r->{input_row});
    },
);

1;
# ABSTRACT:
