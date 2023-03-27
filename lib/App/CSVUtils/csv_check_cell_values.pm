package App::CSVUtils::csv_check_cell_values;

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
    name => 'csv_check_cell_values',
    summary => 'Check the value of single cells of CSV against code/schema/regex',
    description => <<'_',

Example `input.csv`:

    ingredient,%weight
    foo,81
    bar,9
    baz,10

Check that ingredients do not contain number:

    % csv-check-cell-values input.csv -f ingredient --with-regex '/\\A[A-Za-z ]+\\z/'

Check that all %weight is between 0 and 100:

    % csv-check-cell-values input.csv -f %weight --with-code '$_>0 && $_<=100'

_

    add_args => {
        %App::CSVUtils::argspecsopt_field_selection,
        with_code => {
            summary => 'Check with Perl code',
            schema => $App::CSVUtils::sch_req_str_or_code,
            description => <<'_',

Code will be given the value of the cell and should return a true value if value
is valid.

_
        },
        with_schema => {
            summary => 'Check with a Sah schema',
            schema => ['any*', of=>[
                ['str*', min_len=>1], # string schema
                ['array*', max_len=>2], # an array schema
            ]],
            completion => sub {
                require Complete::Module;
                my %args = @_;
                Complete::Module::complete_module(
                    word => $args{word},
                    ns_prefix => "Sah::Schema::",
                );
            },
        },
        with_regex => {
            schema => 're_from_str*',
        },

        quiet => {
            schema => 'bool*',
            cmdline_aliases => {q=>{}},
        },
        print_validated => {
            summary => 'Print the validated values of each cell',
            schema => 'bool*',
            description => <<'_',

When validating with schema, will print each validated (possible coerced,
filtered) value of each cell.

_
        },
    },
    add_args_rels => {
        req_one => ['with_code', 'with_schema', 'with_regex'],
    },

    links => [
        {url=>'prog:csv-check-field-values', summary=>'Check of the values of whole fields'},
    ],
    tags => ['accepts-schema', 'accepts-regex', 'category:checking'],

    examples => [
        {
            summary => 'Check whether the `rank` field has monotonically increasing values',
            argv => ['formula.csv', '-f', 'rank', '--with-schema', 'array/num//monotonically_increasing'],
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],

    writes_csv => 0,

    on_input_data_row => sub {
        my $r = shift;

        # key we add to the stash
        unless (defined $r->{code}) {
            if ($r->{util_args}{with_schema}) {
                require Data::Sah;
                my $sch = $r->{util_args}{with_schema};
                if (!ref($sch)) {
                    $sch =~ s!/!::!g;
                }
                $r->{code} = Data::Sah::gen_validator($sch, {return_type=>"str_errmsg+val"});
            } elsif ($r->{util_args}{with_code}) {
                my $code0 = compile_eval_code($r->{util_args}{with_code}, 'with_code');
                $r->{code} = sub {
                    local $_ = $_[0]; my $res = $code0->($_);
                    [($res ? "":"FAIL"), $res];
                };
            } elsif (defined $r->{util_args}{with_regex}) {
                $r->{code} = sub {
                    $_[0] =~ $r->{util_args}{with_regex} ? ["", $_[0]] : ["Does not match regex $r->{util_args}{with_regex}", $_[0]];
                };
            }
        }

        # key we add to the stash
        unless ($r->{selected_fields_idx_array_sorted}) {
            my $res = App::CSVUtils::_select_fields($r->{input_fields}, $r->{input_fields_idx}, $r->{util_args});
            die $res unless $res->[0] == 100;
            my $selected_fields = $res->[2][0];
            my $selected_fields_idx_array = $res->[2][1];
            die [412, "At least one field must be selected"]
                unless @$selected_fields;
            $r->{selected_fields_idx_array_sorted} = [sort { $b <=> $a } @$selected_fields_idx_array];
        }

        for my $idx (@{ $r->{selected_fields_idx_array_sorted} }) {
            my $res = $r->{code}->( $r->{input_row}[$idx] );
            if ($res->[0]) {
                my $msg = "Row #$r->{input_data_rownum} field '$r->{input_fields}[$idx]': Value '$r->{input_row}[$idx]' does NOT validate: $res->[0]";
                $r->{result} = [400, $msg, $r->{util_args}{quiet} ? undef : $msg];
                $r->{wants_skip_files}++;
            } else {
                if ($r->{util_args}{print_validated}) {
                    print $res->[1], "\n";
                }
            }
        }
    },

    after_close_input_files => sub {
        my $r = shift;

        $r->{result} //= [200, "OK", $r->{util_args}{quiet} ? undef : "All cells validate"];
    },
);

1;
# ABSTRACT:
