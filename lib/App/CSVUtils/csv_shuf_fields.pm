package App::CSVUtils::csv_shuf_fields;

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
    name => 'csv_shuf_fields',
    summary => 'Shuffle CSV fields',
    description => <<'MARKDOWN',

This utility shuffles the order of fields in the CSV. Example input CSV:

    a,b,c,d
    1,2,3,4
    5,6,7,8

Example output CSV:

    d,a,c,b
    4,1,3,2
    8,5,7,6

MARKDOWN

    add_args => {
    },

    tags => ['category:sorting'],

    on_input_header_row => sub {
        my $r = shift;

        require List::Util;
        my @shuffled_indices = List::Util::shuffle(0 .. $#{$r->{input_fields}});

        $r->{output_fields} = [map {$r->{input_fields}[$_]} @shuffled_indices];
        $r->{output_fields_idx_array} = \@shuffled_indices; # this is a key we add to stash
    },

    on_input_data_row => sub {
        my $r = shift;

        my $row = [];
        for my $j (@{ $r->{output_fields_idx_array} }) {
            push @$row, $r->{input_row}[$j];
        }
        $r->{code_print_row}->($row);
    },
);

1;
# ABSTRACT:
