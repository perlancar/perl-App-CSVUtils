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
possible ways ("layouts"): left-to-right first then top-to-bottom, or
bottom-to-top then left-to-right, etc.

Some illustration of the layout:

    % cat 1-to-100.csv
    num
    1
    2
    3
    ...

    % csv-fill-cells 1-to-100.csv --num-rows 10 --num-fields 10 ; # default layout is 'left_to_right_then_top_to_bottom'
    field0,field1,field2,field3,field4,field5,field6,field7,field8,field9
    1,2,3,4,5,6,7,8,9,10
    11,12,13,14,15,16,17,18,19,20
    21,22,23,24,25,26,27,28,29,30
    ...

    % csv-fill-cells 1-to-100.csv --num-rows 10 --num-fields 10 --layout top_to_bottom_then_left_to_right
    field0,field1,field2,field3,field4,field5,field6,field7,field8,field9
    1,11,21,31,41,51,61,71,81,91
    2,12,22,32,42,52,62,72,82,92
    3,13,23,33,43,53,63,73,83,93
    ...

    % csv-fill-cells 1-to-100.csv --num-rows 10 --num-fields 10 --layout top_to_bottom_then_right_to_left
    91,81,71,61,51,41,31,21,11,1
    92,82,72,62,52,42,32,22,12,2
    93,83,73,63,53,43,33,23,13,3
    ...

    % csv-fill-cells 1-to-100.csv --num-rows 10 --num-fields 10 --layout right_to_left_then_top_to_bottom
    10,9,8,7,6,5,4,3,2,1
    20,19,18,17,16,15,14,13,12,11
    30,29,28,27,26,25,24,23,22,21
    ...

Some additional options are available, e.g.: a filter to let skip filling some
cells.

When there are more input values than can be fitted, the extra input values are
not placed into the output CSV.

When there are less input values to fill the specified number of rows, then only
the required number of rows and/or columns will be used.

Additional options planned:

- what to do when there are less values to completely fill the output CSV
  (whether to always expand or expand when necessary, which is the default).

- what to do when there are more values (extend the table or ignore the extra
  input values, which is the default).

_
    add_args => {
        # TODO
        #fields => $App::CSVUtils::argspecopt_fields{fields}, # category:output

        layout => {
            summary => 'Specify how the output CSV is to be filled',
            schema => ['str*', in=>[
                'left_to_right_then_top_to_bottom',
                'right_to_left_then_top_to_bottom',
                'left_to_right_then_bottom_to_top',
                'right_to_left_then_bottom_to_top',
                'top_to_bottom_then_left_to_right',
                'top_to_bottom_then_right_to_left',
                'bottom_to_top_then_left_to_right',
                'bottom_to_top_then_right_to_left',
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
        my $layout = $r->{util_args}{layout} // 'left_to_right_then_top_to_bottom';
        my $output_rows = [];

        my $x = $layout =~ /left_to_right/ ? 0 : $r->{util_args}{num_fields}-1;
        my $y = $layout =~ /top_to_bottom/ ? 1 : $r->{util_args}{num_rows};
        while (1) {
            goto INC_POS if $r->{filter} && !$r->{filter}->($r, $y, $x);

          INC_I:
            $i++;
            last if $i >= @{ $r->{input_values} };

          FILL_CELL:
            for (1 .. $y) {
                $output_rows->[$_-1] //= [map {undef} 1 .. $r->{util_args}{num_fields}];
            }
            $output_rows->[$y-1][$x] = $r->{input_values}[$i];

          INC_POS:
            if ($layout =~ /\A(top|bottom)_/) {
                # vertically first then horizontally
                if ($layout =~ /top_to_bottom/) {
                    $y++;
                    if ($y > $r->{util_args}{num_rows}) {
                        $y = 1;
                        if ($layout =~ /left_to_right/) {
                            $x++;
                            last if $x >= $r->{util_args}{num_fields};
                        } else {
                            $x--;
                            last if $x < 0;
                        }
                    }
                } else {
                    $y--;
                    if ($y < 1) {
                        $y = $r->{util_args}{num_rows};
                        if ($layout =~ /left_to_right/) {
                            $x++;
                            last if $x >= $r->{util_args}{num_fields};
                        } else {
                            $x--;
                            last if $x < 0;
                        }
                    }
                }
            } else {
                # horizontally first then vertically
                if ($layout =~ /left_to_right/) {
                    $x++;
                    if ($x >= $r->{util_args}{num_fields}) {
                        $x = 0;
                        if ($layout =~ /top_to_bottom/) {
                            $y++;
                            last if $y > $r->{util_args}{num_rows};
                        } else {
                            $y--;
                            last if $y < 1;
                        }
                    }
                } else {
                    $x--;
                    if ($x < 0) {
                        $x = $r->{util_args}{num_fields}-1;
                        if ($layout =~ /top_to_bottom/) {
                            $y++;
                            last if $y > $r->{util_args}{num_rows};
                        } else {
                            $y--;
                            last if $y < 1;
                        }
                    }
                }
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
