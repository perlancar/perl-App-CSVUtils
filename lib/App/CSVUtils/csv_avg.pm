package App::CSVUtils::csv_avg;

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
    name => 'csv_avg',
    summary => 'Output a summary row which are arithmetic averages of data rows',
    description => <<'MARKDOWN',

Non-numbers will be assumed to be 0.

Example:

    # students.csv
    name,age
    andi,13
    budi,12
    chandra,12
    dudi,12

    % csv-avg students.csv
    name,age
    0,12.25

    % csv-avg students.csv --with-data-row
    name,age
    andi,13
    budi,12
    chandra,12
    dudi,12
    0,12.25

MARKDOWN
    add_args => {
        %App::CSVUtils::argspecopt_with_data_rows,
    },
    tags => ['adds-row','category:summarizing'],

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
        $r->{code_print_row}->($r->{input_row}) if $r->{util_args}{with_data_rows};
        $r->{row_count}++;
    },

    after_read_input => sub {
        my $r = shift;

        if ($r->{row_count} > 0) {
            for my $j (0 .. $#{ $r->{output_fields} }) {
                $r->{summary_row}[$j] /= $r->{row_count};
            }
        }
        $r->{code_print_row}->($r->{summary_row});
    },
);

1;
# ABSTRACT:
