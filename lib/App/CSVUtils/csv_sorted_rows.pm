package App::CSVUtils::csv_sorted_rows;

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
use App::CSVUtils::csv_sort_rows;

gen_csv_util(
    name => 'csv_sorted_rows',
    summary => 'Check that CSV rows are sorted',
    description => <<'_',

This utility checks that rows in the CSV are sorted according to specified
sorting rule(s). Example `input.csv`:

    name,age
    Andy,20
    Dennis,15
    Ben,30
    Jerry,30

Example check command:

    % csv-sorted-rows input.csv --by-field name; # check if name is ascibetically sorted
    ERROR 400: Rows are NOT sorted

Example `input2.csv`:

    name,age
    Andy,20
    Ben,30
    Dennis,15
    Jerry,30

    % csv-sorted-rows input2.csv --by-field name; # check if name is ascibetically sorted
    Rows are sorted

    % csv-sorted-rows input2.csv --by-field ~name; # check if name is ascibetically sorted in descending order
    ERROR 400: Rows are NOT sorted

See <prog:csv-sort-rows> for details on sorting options.

_

    writes_csv => 0,

    add_args => {
        # KEEP SYNC WITH csv_sort_rows
        %App::CSVUtils::argspecopt_hash,
        %App::CSVUtils::argspecs_sort_rows,

        quiet => {
            summary => 'If set to true, do not show messages',
            schema => 'bool*',
            cmdline_aliases => {q=>{}},
        },
    },

    tags => ['category:checking'],

    on_input_header_row => \&App::CSVUtils::csv_sort_rows::on_input_header_row,

    on_input_data_row => \&App::CSVUtils::csv_sort_rows::on_input_data_row,

    after_close_input_files => sub {
        local $main::_CSV_SORTED_ROWS = 1;
        App::CSVUtils::csv_sort_rows::after_close_input_files(@_);
    },
);

1;
# ABSTRACT:
