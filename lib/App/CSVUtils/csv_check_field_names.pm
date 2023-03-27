package App::CSVUtils::csv_check_field_names;

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
    name => 'csv_check_field_names',
    summary => 'Check field names',
    description => <<'_',

This utility performs the following checks:

- There is at least 1 field;
- There is no duplicate field name;
- There is no field name of '' (empty string);

There will be options to add some additional checks in the future.

_
    add_args => {
    },
    links => [
        {url=>'prog:csv-check-cell-values', summary=>'Check of the values of individual cells'},
    ],
    tags => ['category:checking'],

    examples => [
        {
            summary => 'Check that all field names are valid',
            argv => ['file.csv'],
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],

    writes_csv => 0,

    on_input_header_row => sub {
        my $r = shift;

        die [400, "There must at least be 1 field"] unless @{ $r->{input_fields} };

        my %seen;
        my $i = 0;
        for my $field (@{ $r->{input_fields} }) {
            $i++;
            die [400, "There is a field (#$i) with empty name"] unless length $field;
            die [400, "There is duplicate field (#$i, $field)"] if $seen{$field}++;
        }
    },

    on_input_data_row => sub {
        my $r = shift;
        $r->{wants_skip_files}++;
    },
);

1;
# ABSTRACT:
