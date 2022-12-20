package App::CSVUtils::csv_pick_rows;

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
    name => 'csv_pick_rows',
    summary => 'Return one or more random rows from CSV',
    description => <<'_',


_
    add_args => {
        num_rows => {
            summary => 'Number of rows to pick',
            schema => 'posint*',
            default => 1,
            cmdline_aliases => {n=>{}},
        },
    },

    on_input_header_row => sub {
        my $r = shift;

        # we add this key to the stash
        $r->{picked_rows} = [];

        # because input_* will be cleared by the time of after_read_input,
        # we save and set it now
        $r->{output_fields} = $r->{input_fields};
    },

    on_input_data_row => sub {
        my $r = shift;

        #say "D:input_data_rownum=$r->{input_data_rownum}";
        if ($r->{util_args}{num_rows} == 1) {
            # algorithm from Learning Perl
            $r->{picked_rows}[0] = $r->{input_row} if rand($r->{input_data_rownum}) < 1;
        } else {
            # algorithm from Learning Perl, modified
            if (@{ $r->{picked_rows} } < $r->{util_args}{num_rows}) {
                # we haven't reached $num_rows, put row to result in a random
                # position
                splice @{ $r->{picked_rows} }, rand(@{ $r->{picked_rows} }+1), 0, $r->{input_row};
            } else {
                # we have reached $num_rows, just replace an item randomly,
                # using algorithm from Learning Perl, slightly modified
                rand($r->{input_data_rownum}) < @{ $r->{picked_rows} }
                    and splice @{ $r->{picked_rows} }, rand(@{ $r->{picked_rows} }), 1, $r->{input_row};
            }
        }
    },

    after_read_input => sub {
        my $r = shift;

        for my $row (@{ $r->{picked_rows} }) {
            $r->{code_printrow}->($row);
        }
    },
);

1;
# ABSTRACT:
