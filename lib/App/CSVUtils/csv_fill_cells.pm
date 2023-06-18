package App::CSVUtils::csv_fill_cells;

use 5.010001;
use strict;
use warnings;

# AUTHORITY
# DATE
# DIST
# VERSION

use App::CSVUtils qw(
                        gen_csv_util
                        compile_eval_code
                );

gen_csv_util(
    name => 'csv_fill_cells',
    summary => 'Create a CSV and fill its cells from supplied values (a 1-column CSV)',
    description => <<'_',

This utility takes values (from cells of a 1-column input CSV), creates an
output CSV of specified size, and fills the output CSV in one of several
possible ways (e.g. left-to-right first then top-to-bottom, or bottom-to-top
then left-to-right, etc). Some additional options are available: a filter to let
skip filling some cells,

Additional options planned:

- what to do when there are less values to completely fill the output
  CSV (fill with blanks or leave as-is).

- what to do when there are more values (extend the table or ignore the extra
  input values).

_
    add_args => {
        # TODO
        #fields => $App::CSVUtils::argspecopt_fields{fields}, # category:output

        layout => {
            summary => 'Specify how the output CSV is to be filled',
            schema => ['str*', in=>[
                'left_to_right_then_top_to_bottom',
                #'right_to_left_then_top_to_bottom',
                #'left_to_right_then_bottom_to_top',
                #'right_to_left_then_bottom_to_top',
                #'top_to_bottom_then_left_to_right',
                #'top_to_bottom_then_right_to_left',
                #'bottom_to_top_then_left_to_right',
                #'bottom_to_top_then_right_to_left',
            ]],
            default => 'left_to_right_then_top_to_bottom',
            tags => ['category:layout'],
        },

        filter => {
            summary => 'Code to filter cells to fill',
            schema => 'str*',
            description => <<'_',

Code will be compiled in the `main` package.

Code is passed `($r, $output_row_num, $output_field_idx)` where `$r` is the
stash, `$output_row_num` is a 1-based integer (first data row means 1), and
`$output_field_idx` is the 0-based field index (0 means the first index). Code
is expected to return a boolean value, where true meaning the cell should be
filied.

_
            tags => ['category:filtering'],
        },
        num_rows => {
            summary => 'Number of rows of the output CSV',
            schema => 'posint*',
            req => 1,
            tags => ['category:output'],
        },
        num_fields => {
            summary => 'Number of fields of the output CSV',
            schema => 'posint*',
            req => 1,
            tags => ['category:output'],
        },
    },

    tags => ['category:generating', 'accepts-code'],

    examples => [
        {
            summary => 'Fill number 1..100 into a 10x10 grid',
            src => q{seq 1 100 | [[prog]] --num-rows 10 --num-fields 10},
            src_plang => 'bash',
            test => 0,
        },
    ],

    on_input_header_row => sub {
        my $r = shift;

        # set output fields
        $r->{output_fields} = [ map {"field$_"}
                                0 .. $r->{util_args}{num_fields}-1 ];

        # compile filter
        if ($r->{util_args}{filter}) {
            my $code = compile_eval_code($r->{util_args}{filter}, 'filter');
            # this is a key we add to the stash
            $r->{filter} = $code;
        }

        # this is a key we add to the stash
        $r->{input_values} = [];
    },

    on_input_data_row => sub {
        my $r = shift;

        push @{ $r->{input_values} }, $r->{input_row}[0];
    },

    after_read_input => sub {
        my $r = shift;

        my $i = -1;
        my $x = 0;
        my $y = 1;
        my $output_rows = [];
        while (1) {
            $i++;
            last if $i >= @{ $r->{input_values} };
            $output_rows->[$y] //= [map {undef} 1 .. $r->{util_args}{num_fields}];
            if (!$r->{filter} || $r->{filter}->(0, $y, $x)) {
                $output_rows->[$y][$x] = $r->{input_values}[$i];
            }
            $x++;
            if ($x >= $r->{util_args}{num_fields}) {
                $x = 0;
                $y++;
            }
        }

        # print rows
        for my $row (@$output_rows) {
            $r->{code_print_row}->($row);
        }
    },
);

1;
# ABSTRACT:
