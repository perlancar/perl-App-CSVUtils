package App::CSVUtils::csv_transpose;

use 5.010001;
use strict;
use warnings;

# AUTHORITY
# DATE
# DIST
# VERSION

use App::CSVUtils qw(gen_csv_util);

gen_csv_util(
    name => 'csv_transpose',
    summary => 'Transpose a CSV',
    description => <<'_',

This utility transpose a CSV file: rows will become fields and vice versa.

Example:

    # input.csv
    name,age
    andi,17
    budi,22
    chandra,19
    dudi,20

    % csv-transpose input.csv
    row0,row1,row2,row3,row4
    name,andi,budi,chandra,dudi
    age,17,22,19,22

    % csv-transpose input.csv --no-output-header
    name,andi,budi,chandra,dudi
    age,17,22,19,22

_

    add_args => {
    },
    examples => [
        {
            summary => 'Transpose a CSV',
            argv => ['file.csv'],
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],

    on_input_header_row => sub {
        my $r = shift;

        # this is a key we add ourselves
        $r->{transposed_rows} = [];

        for my $j (0 .. $#{ $r->{input_fields} }) {
            $r->{transposed_rows}[ $j ] //= [];
            $r->{transposed_rows}[ $j ][0] = $r->{input_fields}[$j];
        }

        $r->{output_fields} = ["row1"];
    },

    on_input_data_row => sub {
        my $r = shift;

        my $i = $r->{input_rownum};
        push @{ $r->{output_fields} }, "row$i";
        for my $j (0 .. $#{ $r->{input_row} }) {
            $r->{transposed_rows}[ $j ][ $i-1 ] =
                $r->{input_row}[$j];
        }
    },

    after_close_input_files => sub {
        my $r = shift;

        for my $row (@{ $r->{transposed_rows} }) {
            $r->{code_print_row}->($row);
        }
    },
);

1;
# ABSTRACT:
