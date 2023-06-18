package App::CSVUtils::csv_get_cells;

use 5.010001;
use strict;
use warnings;

# AUTHORITY
# DATE
# DIST
# VERSION

use App::CSVUtils qw(gen_csv_util);

gen_csv_util(
    name => 'csv_get_cells',
    summary => 'Get one or more cells from CSV',
    description => <<'_',

This utility lets you specify "coordinates" of cell locations to extract. Each
coordinate is in the form of `<field>,<row>` where `<field>` is the field name
or position (1-based, so 1 is the first field) and `<row>` is the row position
(1-based, so 1 is the header row and 2 is the first data row).

_

    add_args => {
        coordinates => {
            'x.name.is_plural' => 1,
            'x.name.singular' => 'coordinate',
            summary => 'List of coordinates, each in the form of <col>,<row> e.g. age,1 or 1,1',
            schema => ['array*', of=>'str*', min_len=>1],
            req => 1,
            pos => 1,
            slurpy => 1,
        },
    },
    examples => [
        {
            summary => 'Get the age for second row',
            argv => ['file.csv', 'age,2'],
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],

    writes_csv => 0,

    tags => ['category:extracting'],

    on_input_data_row => sub {
        my $r = shift;

        # this is the key we add to stash
        $r->{cells} //= [];

        my $j = -1;
      COORD:
        for my $coord (@{ $r->{util_args}{coordinates} }) {
            $j++;
            my ($coord_field, $coord_row) = $coord =~ /\A(.+),(.+)\z/
                or die [400, "Invalid coordinate '$coord': must be in field,row form"];
            $coord_row =~ /\A[0-9]+\z/
                or die [400, "Invalid coordinate '$coord': invalid row syntax '$coord_row', must be a number"];
            my $row;
            if ($coord_row == 1) {
                $row = $r->{input_fields};
            } elsif ($coord_row == $r->{input_rownum}) {
                $row = $r->{input_row};
            } else {
                next COORD;
            }

            if ($coord_field =~ /\A[0-9]+\z/) {
                $coord_field >= 1 && $coord_field <= $#{ $r->{input_fields} }+1
                        or die [400, "Invalid coordinate '$coord': field number '$coord_field' out of bound, must be between 1-". ($#{$r->{input_fields}}+1)];
                $r->{cells}[$j] = $row->[$coord_field-1];
            } else {
                my $field_idx = App::CSVUtils::_find_field($r->{input_fields}, $coord_field);
                $r->{cells}[$j] = $row->[ $field_idx ];
            }
        }
    },

    after_close_input_files => sub {
        my $r = shift;

        $r->{result} = [200, "OK", $r->{cells}];
    },
);

1;
# ABSTRACT:
