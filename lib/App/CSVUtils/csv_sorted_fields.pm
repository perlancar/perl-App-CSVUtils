package App::CSVUtils::csv_sorted_fields;

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
use App::CSVUtils::csv_sort_fields;

gen_csv_util(
    name => 'csv_sorted_fields',
    summary => 'Check that CSV fields are sorted',
    description => <<'MARKDOWN',

This utility checks that fields in the CSV are sorted according to specified
sorting rule(s). Example `input.csv`:

    b,c,a
    1,2,3
    4,5,6

Example check command:

    % csv-sorted-fields input.csv; # check if the fields are ascibetically sorted
    ERROR 400: Fields are NOT sorted

Example `input2.csv`:

    c,b,a
    1,2,3
    4,5,6

    % csv-sorted-fields input2.csv -r
    Fields are sorted

See <prog:csv-sort-fields> for details on sorting options.

MARKDOWN

    writes_csv => 0,

    tags => ['category:checking'],

    add_args => {
        # KEEP SYNC WITH csv_sort_fields
        %App::CSVUtils::argspecs_sort_fields,

        quiet => {
            summary => 'If set to true, do not show messages',
            schema => 'bool*',
            cmdline_aliases => {q=>{}},
        },
    },

    # KEEP SYNC WITH csv_sort_fields
    add_args_rels => {
        choose_one => ['by_examples', 'by_code', 'by_sortsub'],
    },

    on_input_header_row => sub {
        local $main::_CSV_SORTED_FIELDS = 1;
        App::CSVUtils::csv_sort_fields::on_input_header_row(@_);
    },

    on_input_data_row => sub {
        local $main::_CSV_SORTED_FIELDS = 1;
        App::CSVUtils::csv_sort_fields::on_input_data_row(@_);
    },
);

1;
# ABSTRACT:
