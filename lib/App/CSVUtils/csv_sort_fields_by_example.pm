package App::CSVUtils::csv_sort_fields_by_example;

use 5.010001;
use strict;
use warnings;

# AUTHORITY
# DATE
# DIST
# VERSION

use App::CSVUtils;
use App::CSVUtils::csv_sort_fields;
use Perinci::Sub::Util qw(gen_modified_sub);

my $res = gen_modified_sub(
    output_name => 'csv_sort_fields_by_example',
    base_name => 'App::CSVUtils::csv_sort_fields::csv_sort_fields',
    summary => 'Sort CSV fields by example',
    description => <<'MARKDOWN',

This is a thin wrapper for <prog:csv-sort-fields>, which can already sort fields
by example but you have to specify it as a series of `--by-example` options:

    % csv-sort-fields in.csv --by-example c --by-example g --by-example d

This utility allows you to say:

    % csv-sort-fields-by-example in.csv c g d

Example:

    # in.csv
    a,b,c,d,e,f,g
    1,2,3,4,5,6,7

    % csv-sort-fields-by-example in.csv c g d
    c,g,d,a,b,e,f
    3,7,4,1,2,5,6

MARKDOWN
    remove_args => ['by_examples', 'by_code', 'by_sortsub'],
    add_args => {
        fields => {
            'x.name.is_plural' => 1,
            'x.name.singular' => 'field',
            summary => 'Fields for examples',
            'summary.alt.plurality.singular' => 'Add field for example',
            schema => ['array*', of=>'str*'],
            req => 1,
            pos => 1,
            slurpy => 1,
            cmdline_aliases => {f=>{}},
            completion => \&App::CSVUtils::_complete_field,
        },
    },
    modify_args => {
        output_filename => sub {
            my $argspec = shift;
            delete $argspec->{pos};
        },
    },
    tags => ['category:sorting'],
    output_code => sub {
        my %args = @_;
        my $examples = delete $args{fields};
        App::CSVUtils::csv_sort_fields::csv_sort_fields(
            %args,
            by_examples => $examples,
        );
    },
);

1;
# ABSTRACT:

=for Pod::Coverage ^(on|after|before)_.+$
