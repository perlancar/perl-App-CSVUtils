package App::CSVUtils::csv_find_values;

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
    name => 'csv_find_values',
    summary => 'Find specified values in a CSV field',
    description => <<'_',

Example input:

    # product.csv
    sku,name,is_active,description
    SKU1,foo,1,blah
    SK2,bar,1,blah
    SK3B,baz,0,blah
    SKU2,qux,1,blah
    SKU3,quux,1,blah
    SKU14,corge,0,blah

Check whether specified values are found in the `sku` field, print message when
they are (search case-insensitively):

    % csv-find-values product.csv sku sku1 sk3b sku15 -i
    'sku1' is found in field 'sku' row 2
    'sk3b' is found in field 'sku' row 4

Print message when values are *not* found instead:

    % csv-find-values product.csv sku sku1 sk3b sku15 -i --print-when=not_found
    'sku15' is NOT found in field 'sku'

Always print message:

    % csv-find-values product.csv sku sku1 sk3b sku15 -i --print-when=always
    'sku1' is found in field 'sku' row 2
    'sk3b' is found in field 'sku' row 4
    'sku15' is NOT found in field 'sku'

Do custom action with Perl code, code will receive `$_` (the value being
evaluated), `$found` (bool, whether it is found in the field), `$rownum` (the
row number the value is found in), `$data_rownum` (the data row number the value
is found in, equals `$rownum` - 1):

    % csv-find-values product.csv sku1 sk3b sku15 -i -e 'if ($found) { print "$_ found\n" } else { print "$_ NOT found\n" }'
    sku1 found
    sk3b found
    sku15 NOT found

There is an option to do fuzzy matching, where similar values will be suggested
when exact match is not found.

_
    add_args => {
        ignore_case => {
            schema => 'bool*',
            cmdline_aliases => {ci=>{}, i=>{}},
            tags => ['category:searching'],
        },
        fuzzy => {
            schema => 'true*',
            tags => ['category:searching'],
        },

        %App::CSVUtils::argspec_field_1,

        values => {
            'x.name.is_plural' => 1,
            'x.name.singular' => 'value',
            schema => ['array*', of=>'str*', min_len=>1],
            req => 1,
            pos => 2,
            slurpy => 1,
        },
        print_when => {
            schema => ['str*', in=>[qw/found not_found always/]],
            default => 'found',
            description => <<'_',

Overriden by the `--eval` option.

_
            tags => ['category:output'],
        },
        %App::CSVUtils::argspecopt_eval,
    },

    writes_csv => 0,

    tags => ['category:searching'],

    on_input_header_row => sub {
        my $r = shift;

        # check arguments
        my $field = $r->{util_args}{field};
        my $field_idx = App::CSVUtils::_select_field($r->{input_fields}, $field);

        # we add the following keys to the stash
        $r->{field} = $field;
        $r->{field_idx} = $field_idx;
        $r->{code} = compile_eval_code($r->{util_args}{eval}, 'eval') if defined $r->{util_args}{eval};
        $r->{csv_values} = [];
        $r->{search_values} = $r->{util_args}{ignore_case} ?
            [ map { lc } @{ $r->{util_args}{values} }] : $r->{util_args}{values};
    },

    on_input_data_row => sub {
        my $r = shift;

        my $val = ($r->{input_row}[ $r->{field_idx} ] // '');
        if ($r->{util_args}{ignore_case}) { $val = lc $val }
        push @{ $r->{csv_values} }, $val;
    },

    after_close_input_files => sub {
        my $r = shift;

        my $ci = $r->{util_args}{ignore_case};

        my $maxdist;
        for my $i (0 .. $#{ $r->{util_args}{values} }) {
            my $value = $r->{util_args}{values}[$i];
            my $search_value = $r->{search_values}[$i];
            my $found_rownum;

            my $j = 0;
            for my $v (@{ $r->{csv_values} }) {
                $j++;
                if ($v eq $search_value) { $found_rownum = $j; last }
            }

            my $suggested_values;
            if (!defined($found_rownum) && $r->{util_args}{fuzzy}) {
                # XXX with this, we do exact matching twice
                require Complete::Util;
                local $Complete::Common::OPT_CI = 1;
                local $Complete::Common::OPT_MAP_CASE = 0;
                local $Complete::Common::OPT_WORD_MODE = 0;
                local $Complete::Common::OPT_CHAR_MODE = 0;
                local $Complete::Common::OPT_FUZZY = 1;
                $suggested_values = Complete::Util::complete_array_elem(
                    array => $r->{csv_values},
                    word => $value,
                );
            }

            if ($r->{code}) {
                {
                    local $_ = $value;
                    local $main::found = defined $found_rownum ? 1:0;
                    local $main::rownum = $found_rownum+1;
                    local $main::data_rownum = $found_rownum;
                    local $main::r = $r;
                    local $main::csv = $r->{input_parser};
                    $r->{code}->($_);
                }
            } else {
                if (defined $found_rownum) {
                    if ($r->{util_args}{print_when} eq 'found' || $r->{util_args}{print_when} eq 'always') {
                        print "'$value' is found in field '$r->{field}' row ".($found_rownum+1)."\n";
                    }
                } else {
                    if ($r->{util_args}{print_when} eq 'not_found' || $r->{util_args}{print_when} eq 'always') {
                        print "'$value' is NOT found in field '$r->{field}'".($suggested_values && @$suggested_values ? ", perhaps you meant ".join("/", @$suggested_values)."?" : "")."\n";
                    }
                }
            }
        }
    },
);

1;
# ABSTRACT:
