package App::CSVUtils::csv_shuf_rows;

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
    name => 'csv_shuf_rows',
    summary => 'Shuffle CSV rows',
    description => <<'MARKDOWN',

This utility shuffle the rows in the CSV. Example input CSV:

    name,age
    Andy,20
    Dennis,15
    Ben,30
    Jerry,30

Example output CSV:

    name,age
    Ben,30
    Andy,20
    Jerry,30
    Dennis,15

MARKDOWN

    add_args => {
    },

    tags => ['category:sorting'],

    on_input_data_row => sub {
        my $r = shift;

        # keys we add to the stash
        $r->{input_rows} //= [];

        push @{ $r->{input_rows} }, $r->{input_row};
    },

    after_close_input_files => sub {
        my $r = shift;

        # we do the actual shuffling here after collecting all the rows

        require List::Util;
        my $shuffled_rows = [List::Util::shuffle(@{$r->{input_rows}})];

        for my $row (@$shuffled_rows) {
            $r->{code_print_row}->($row);
        }
    },
);

1;
# ABSTRACT:
