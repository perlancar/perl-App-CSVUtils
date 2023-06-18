package App::CSVUtils::csv_pick_cells;

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
    name => 'csv_pick_cells',
    summary => 'Get one or more random cells from CSV',
    description => <<'_',

The values will be returned as a 1-column CSV.

_
    add_args => {
        num_cells => {
            summary => 'Number of cells to pick',
            schema => 'posint*',
            default => 1,
            cmdline_aliases => {n=>{}},
        },
    },
    tags => ['category:extracting', 'random'],

    examples => [
        {
            summary => 'Pick a random cell value from CSV',
            argv => ['file.csv'],
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'Pick 5 random cell values from CSV, do not output header row',
            argv => ['file.csv', '-n5', '--no-output-header'],
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],

    on_input_header_row => sub {
        my $r = shift;

        # we add this key to the stash
        $r->{picked_cells} = [];
        $r->{num_cells} = 0;

        $r->{output_fields} = ['value'];
    },

    on_input_data_row => sub {
        my $r = shift;

        #say "D:input_data_rownum=$r->{input_data_rownum}";
        if ($r->{util_args}{num_cells} == 1) {
            for my $i (0 .. $#{ $r->{input_fields} }) {
                # algorithm from Learning Perl
                $r->{picked_cells}[0] = $r->{input_row}[$i]
                    if rand(++$r->{num_cells}) < 1;
            }
        } else {
            for my $i (0 .. $#{ $r->{input_fields} }) {
                $r->{num_cells}++;
                # algorithm from Learning Perl, modified
                if (@{ $r->{picked_cells} } < $r->{util_args}{num_cells}) {
                    # we haven't reached $num_cells, put cell to result in a
                    # random position
                    splice @{ $r->{picked_cells} }, rand(@{ $r->{picked_cells} }+1), 0, $r->{input_row}[$i];
                } else {
                    # we have reached $num_cells, just replace an item randomly,
                    # using algorithm from Learning Perl, slightly modified
                    rand($r->{num_cells}) < @{ $r->{picked_cells} }
                        and splice @{ $r->{picked_cells} }, rand(@{ $r->{picked_cells} }), 1, $r->{input_row}[$i];
                }
            }
        }
    },

    after_read_input => sub {
        my $r = shift;

        for my $value (@{ $r->{picked_cells} }) {
            $r->{code_print_row}->([$value]);
        }
    },
);

1;
# ABSTRACT:
