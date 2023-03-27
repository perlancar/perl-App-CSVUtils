package App::CSVUtils::csv_sort_fields;

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
                        compile_eval_code
                );

sub on_input_header_row {
    my $r = shift;

    my $code;
    my $code_gets_field_with_pos;
    if ($r->{util_args}{by_code}) {
        $code_gets_field_with_pos++;
        $code = compile_eval_code($r->{util_args}{by_code}, 'by_code');
    } elsif (defined $r->{util_args}{by_sortsub}) {
        require Sort::Sub;
        $code = Sort::Sub::get_sorter(
            $r->{util_args}{by_sortsub}, $r->{util_args}{sortsub_args});
    } elsif (my $eg = $r->{util_args}{by_examples}) {
        require Sort::ByExample;
        $code = Sort::ByExample->cmp($eg);
    } else {
        $code = sub { $_[0] cmp $_[1] };
    }

    my @sorted_indices = sort {
        my $field_a = $r->{util_args}{ci} ? lc($r->{input_fields}[$a]) : $r->{input_fields}[$a];
        my $field_b = $r->{util_args}{ci} ? lc($r->{input_fields}[$b]) : $r->{input_fields}[$b];
        local $main::a = $code_gets_field_with_pos ? [$field_a, $a] : $field_a;
        local $main::b = $code_gets_field_with_pos ? [$field_b, $b] : $field_b;
        ($r->{util_args}{reverse} ? -1:1) * $code->($main::a, $main::b);
    } 0..$#{$r->{input_fields}};

    $r->{output_fields} = [map {$r->{input_fields}[$_]} @sorted_indices];
    $r->{output_fields_idx_array} = \@sorted_indices; # this is a key we add to stash
}

sub on_input_data_row {
    my $r = shift;

    if ($main::_CSV_SORTED_FIELDS) {
        require Data::Cmp;
        #use DD; dd $r->{input_fields}; print "\n"; dd $r->{output_fields};
        if (Data::Cmp::cmp_data($r->{input_fields}, $r->{output_fields})) {
            # not sorted
            $r->{result} = [400, "NOT sorted", $r->{util_args}{quiet} ? undef : "Fields are NOT sorted"];
        } else {
            # sorted
            $r->{result} = [200, "Sorted", $r->{util_args}{quiet} ? undef : "Fields are sorted"];
        }
        $r->{wants_skip_files}++;
        return;
    } else {
        my $row = [];
        for my $j (@{ $r->{output_fields_idx_array} }) {
            push @$row, $r->{input_row}[$j];
        }
        $r->{code_print_row}->($row);
    }
}

gen_csv_util(
    name => 'csv_sort_fields',
    summary => 'Sort CSV fields',
    description => <<'_',

This utility sorts the order of fields in the CSV. Example input CSV:

    b,c,a
    1,2,3
    4,5,6

Example output CSV:

    a,b,c
    3,1,2
    6,4,5

You can also reverse the sort order (`-r`), sort case-insensitively (`-i`), or
provides the ordering example, e.g. `--by-examples-json '["a","c","b"]'`, or use
`--by-code` or `--by-sortsub`.

_

    add_args => {
        %App::CSVUtils::argspecs_sort_fields,
    },
    add_args_rels => {
        choose_one => ['by_examples', 'by_code', 'by_sortsub'],
    },

    tags => ['category:sorting'],

    on_input_header_row => \&on_input_header_row,

    on_input_data_row => \&on_input_data_row,

);

1;
# ABSTRACT:

=for Pod::Coverage ^(on|after|before)_.+$
