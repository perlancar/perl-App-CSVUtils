package App::CSVUtils::csv_sum;

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
    name => 'csv_sum',
    summary => 'Output a summary row which are arithmetic sum of data rows',
    description => <<'_',

Non-numbers will be assumed to be 0.

Example:

    # students.csv
    name,score
    andi,130
    budi,120
    chandra,120
    dudi,120

    % csv-sum students.csv
    name,score
    0,490

    % csv-sum students.csv --with-data-row
    name,score
    andi,130
    budi,120
    chandra,120
    dudi,120
    0,12.25

_
    add_args => {
        %App::CSVUtils::argspecopt_with_data_rows,
    },

    on_input_header_row => sub {
        my $r = shift;

        # we add this key to the stash
        $r->{summary_row} = [map {0} @{$r->{input_fields}}];
        $r->{row_count} = 0;

        # because input_* will be cleared by the time of after_read_input,
        # we save and set it now
        $r->{output_fields} = $r->{input_fields};
    },

    on_input_data_row => sub {
        my $r = shift;

        for my $j (0 .. $#{ $r->{input_fields} }) {
            no warnings 'numeric', 'uninitialized';
            $r->{summary_row}[$j] += $r->{input_row}[$j]+0;
        }
        $r->{code_printrow}->($r->{input_row}) if $r->{util_args}{with_data_rows};
        $r->{row_count}++;
    },

    after_read_input => sub {
        my $r = shift;

        $r->{code_printrow}->($r->{summary_row});
    },
);

1;
# ABSTRACT:
