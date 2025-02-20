package App::CSVUtils::csv_check_field_values;

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

gen_csv_util(
    name => 'csv_check_field_values',
    summary => 'Check the values of whole fields against code/schema',
    description => <<'MARKDOWN',

Example `input.csv`:

    ingredient,%weight
    foo,81
    bar,9
    baz,10

Example `input2.csv`:

    ingredient,%weight
    foo,81
    bar,9
    baz,10

Check that ingredients are sorted in descending %weight:

    % csv-check-field-values input.csv %weight --with-schema array::num::rev_sorted
    ERROR 400: Field '%weight' does not validate with schema 'array::num::rev_sorted'

    % csv-check-field-values input2.csv %weight --with-schema array::num::rev_sorted
    Field '%weight' validates with schema 'array::num::rev_sorted'

MARKDOWN

    add_args => {
        %App::CSVUtils::argspec_field_1,
        with_code => {
            summary => 'Check with Perl code',
            schema => $App::CSVUtils::sch_req_str_or_code,
            description => <<'MARKDOWN',

Code will be given the value of the rows of the field as an array of scalars and
should return a true value if value is valid.

MARKDOWN
        },
        with_schema => {
            summary => 'Check with a Sah schema module',
            schema => ['any*', of=>[
                ['str*', min_len=>1], # string schema
                ['array*', max_len=>2], # an array schema
            ]],
            description => <<'MARKDOWN',

Should be the name of a Sah schema module without the `Sah::Schema::` prefix,
typically in the `Sah::Schema::array::` subnamespace.

MARKDOWN
            completion => sub {
                require Complete::Module;
                my %args = @_;
                $args{word} = "array/" unless length $args{word};
                Complete::Module::complete_module(
                    word => $args{word},
                    ns_prefix => "Sah::Schema::",
                );
            },
        },
        quiet => {
            schema => 'bool*',
            cmdline_aliases => {q=>{}},
        },
    },
    add_args_rels => {
        req_one => ['with_code', 'with_schema'],
    },
    links => [
        {url=>'prog:csv-check-cell-values', summary=>'Check single-cell values'},
        {url=>'prog:csv-check-field-names', summary=>'Check the field names'},
    ],
    tags => ['category:checking', 'accepts-schema', 'accepts-code',
             #'accepts-regex',
         ],

    writes_csv => 0,

    on_input_data_row => sub {
        my $r = shift;

        # keys we add to the stash
        $r->{value} //= [];

        push @{ $r->{value} }, $r->{input_row}[ $r->{input_fields_idx}{ $r->{util_args}{field} } ];
    },

    after_close_input_files => sub {
        my $r = shift;

        if ($r->{util_args}{with_schema}) {
            require Data::Dmp;
            require Data::Sah;
            my $sch = $r->{util_args}{with_schema};
            if (!ref($sch)) {
                $sch =~ s!/!::!g;
            }
            my $vdr = Data::Sah::gen_validator($sch, {return_type=>"str_errmsg"});
            my $res = $vdr->($r->{value});
            if ($res) {
                my $msg = "Field '$r->{util_args}{field}' does NOT validate with schema ".Data::Dmp::dmp($sch).": $res";
                $r->{result} = [400, $msg, $r->{util_args}{quiet} ? undef : $msg];
            } else {
                my $msg = "Field '$r->{util_args}{field}' validates with schema ".Data::Dmp::dmp($sch);
                $r->{result} = [200, "Sorted", $r->{util_args}{quiet} ? undef : $msg];
            }
        } elsif ($r->{util_args}{with_code}) {
            my $code = compile_eval_code($r->{util_args}{with_code}, 'with_code');
            my $res; { local $_ = $r->{value}; $res = $code->($_) }
            if (!$res) {
                my $msg = "Field '$r->{util_args}{field}' does NOT validate with code'";
                $r->{result} = [400, $msg, $r->{util_args}{quiet} ? undef : $msg];
            } else {
                my $msg = "Field '$r->{util_args}{field}' validates with code";
                $r->{result} = [200, "Sorted", $r->{util_args}{quiet} ? undef : $msg];
            }
        }
    },
);

1;
# ABSTRACT:
