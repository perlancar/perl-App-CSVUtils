package App::CSVUtils::csv_pick_fields;

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
    name => 'csv_pick_fields',
    summary => 'Select one or more random fields from CSV',
    description => <<'_',


_
    add_args => {
        num_fields => {
            summary => 'Number of fields to pick',
            schema => 'posint*',
            default => 1,
            cmdline_aliases => {n=>{}},
        },
    },
    tags => ['category:extracting', 'random'],

    examples => [
        {
            summary => 'Pick 2 random fields row from CSV',
            argv => ['file.csv'],
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],

    on_input_header_row => sub {
        my $r = shift;

        require List::Util;
        my @randomized_fields = List::Util::shuffle(@{ $r->{input_fields} });
        if ($r->{util_args}{num_fields} < @randomized_fields) {
            splice @randomized_fields, 0, (@randomized_fields-$r->{util_args}{num_fields});
        }
        $r->{output_fields} = \@randomized_fields;
    },

    on_input_data_row => sub {
        my $r = shift;

        my $row = [];
        for my $j (0 .. $#{ $r->{output_fields} }) {
            $row->[$j] = $r->{input_row}[ $r->{input_fields_idx}{ $r->{output_fields}[$j] } ];
        }
        $r->{code_print_row}->($row);
    },
);

1;
# ABSTRACT:
