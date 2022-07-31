package App::CSVUtils;

use 5.010001;
use strict;
use warnings;
use Log::ger;

use Hash::Subset qw(hash_subset);

# AUTHORITY
# DATE
# DIST
# VERSION

our %SPEC;

sub _compile {
    my $str = shift;
    return $str if ref $str eq 'CODE';
    defined($str) && length($str) or die "Please specify code (-e)\n";
    $str = "package main; no strict; no warnings; sub { $str }";
    log_trace "Compiling Perl code: $str";
    my $code = eval $str; ## no critic: BuiltinFunctions::ProhibitStringyEval
    die "Can't compile code (-e) '$str': $@\n" if $@;
    $code;
}

sub _get_field_idx {
    my ($field, $field_idxs) = @_;
    defined($field) && length($field) or die "Please specify field (-F)\n";
    my $idx = $field_idxs->{$field};
    die "Unknown field '$field' (known fields include: ".
        join(", ", map { "'$_'" } sort {$field_idxs->{$a} <=> $field_idxs->{$b}}
             keys %$field_idxs).")\n" unless defined $idx;
    $idx;
}

sub _get_csv_row {
    my ($csv, $row, $i, $outputs_header) = @_;
    #use DD; print "  "; dd $row;
    return "" if $i == 1 && !$outputs_header;
    my $status = $csv->combine(@$row)
        or die "Error in line $i: ".$csv->error_input."\n";
    $csv->string . "\n";
}

sub _instantiate_parser_default {
    require Text::CSV_XS;

    Text::CSV_XS->new({binary=>1});
}

sub _instantiate_parser {
    require Text::CSV_XS;

    my ($args, $prefix) = @_;
    $prefix //= '';

    my %tcsv_opts = (binary=>1);
    if (defined $args->{"${prefix}sep_char"} ||
            defined $args->{"${prefix}quote_char"} ||
            defined $args->{"${prefix}escape_char"}) {
        $tcsv_opts{"sep_char"}    = $args->{"${prefix}sep_char"}    if defined $args->{"${prefix}sep_char"};
        $tcsv_opts{"quote_char"}  = $args->{"${prefix}quote_char"}  if defined $args->{"${prefix}quote_char"};
        $tcsv_opts{"escape_char"} = $args->{"${prefix}escape_char"} if defined $args->{"${prefix}escape_char"};
    } elsif ($args->{tsv}) {
        $tcsv_opts{"sep_char"}    = "\t";
        $tcsv_opts{"quote_char"}  = undef;
        $tcsv_opts{"escape_char"} = undef;
    }

    Text::CSV_XS->new(\%tcsv_opts);
}

sub _instantiate_emitter {
    my $args = shift;
    _instantiate_parser($args, 'output_');
}

sub _complete_field_or_field_list {
    # return list of known fields of a CSV

    my $which = shift;

    my %args = @_;
    my $word = $args{word} // '';
    my $cmdline = $args{cmdline};
    my $r = $args{r};

    # we are not called from cmdline, bail
    return undef unless $cmdline; ## no critic: Subroutines::ProhibitExplicitReturnUndef

    # let's parse argv first
    my $args;
    {
        # this is not activated yet
        $r->{read_config} = 1;

        my $res = $cmdline->parse_argv($r);
        #return undef unless $res->[0] == 200;

        $cmdline->_read_config($r) unless $r->{config};
        $args = $res->[2];
    }

    # user hasn't specified -f, bail
    return undef unless defined $args && $args->{filename}; ## no critic: Subroutines::ProhibitExplicitReturnUndef

    # user wants to read CSV from stdin, bail
    return undef if $args->{filename} eq '-'; ## no critic: Subroutines::ProhibitExplicitReturnUndef

    # can the file be opened?
    my $csv_parser = _instantiate_parser(\%args);
    open my($fh), "<encoding(utf8)", $args->{filename} or do {
        #warn "csvutils: Cannot open file '$args->{filename}': $!\n";
        return [];
    };

    # can the header row be read?
    my $row = $csv_parser->getline($fh) or return [];

    if (defined $args->{header} && !$args->{header}) {
        $row = [map {"field$_"} 1 .. @$row];
    }

    require Complete::Util;
    if ($which eq 'field') {
        return Complete::Util::complete_array_elem(
            word => $word,
            array => $row,
        );
    } else {
        # field_list
        # XXX sort_field_list: add optional -/~/+ prefix to field name
        return Complete::Util::complete_comma_sep(
            word => $word,
            elems => $row,
            uniq => 1,
        );
    }
}

sub _complete_field {
    _complete_field_or_field_list('field', @_);
}

sub _complete_field_list {
    _complete_field_or_field_list('field_list', @_);
}

sub _complete_sort_field_list {
    _complete_field_or_field_list('sort_field_list', @_);
}

our %args_common = (
    header => {
        summary => 'Whether input CSV has a header row',
        schema => 'bool*',
        default => 1,
        description => <<'_',

By default (`--header`), the first row of the CSV will be assumed to contain
field names (and the second row contains the first data row). When you declare
that CSV does not have header row (`--no-header`), the first row of the CSV is
assumed to contain the first data row. Fields will be named `field1`, `field2`,
and so on.

_
        cmdline_aliases => {input_header=>{}},
        tags => ['category:input'],
    },
    tsv => {
        summary => "Inform that input file is in TSV (tab-separated) format instead of CSV",
        schema => 'bool*',
        description => <<'_',

Overriden by `--sep-char`, `--quote-char`, `--escape-char` options. If one of
those options is specified, then `--tsv` will be ignored.

_
        cmdline_aliases => {input_tsv=>{}},
        tags => ['category:input'],
    },
    sep_char => {
        summary => 'Specify field separator character in input CSV, will be passed to Text::CSV_XS',
        schema => ['str*', len=>1],
        description => <<'_',

Defaults to `,` (comma). Overrides `--tsv` option.

_
        tags => ['category:input'],
    },
    quote_char => {
        summary => 'Specify field quote character in input CSV, will be passed to Text::CSV_XS',
        schema => ['str*', len=>1],
        description => <<'_',

Defaults to `"` (double quote). Overrides `--tsv` option.

_
        tags => ['category:input'],
    },
    escape_char => {
        summary => 'Specify character to escape value in field in input CSV, will be passed to Text::CSV_XS',
        schema => ['str*', len=>1],
        description => <<'_',

Defaults to `\\` (backslash). Overrides `--tsv` option.

_
        tags => ['category:input'],
    },
);

our %args_csv_output = (
    output_header => {
        summary => 'Whether output CSV should have a header row',
        schema => 'bool*',
        description => <<'_',

By default, a header row will be output *if* input CSV has header row. Under
`--output-header`, a header row will be output even if input CSV does not have
header row (value will be something like "col0,col1,..."). Under
`--no-output-header`, header row will *not* be printed even if input CSV has
header row. So this option can be used to unconditionally add or remove header
row.

_
        tags => ['category:output'],
    },
    output_tsv => {
        summary => "Inform that output file is TSV (tab-separated) format instead of CSV",
        schema => 'bool*',
        description => <<'_',

This is like `--tsv` option but for output instead of input.

Overriden by `--output-sep-char`, `--output-quote-char`, `--output-escape-char`
options. If one of those options is specified, then `--output-tsv` will be
ignored.

_
        tags => ['category:output'],
    },
    output_sep_char => {
        summary => 'Specify field separator character in output CSV, will be passed to Text::CSV_XS',
        schema => ['str*', len=>1],
        description => <<'_',

This is like `--sep-char` option but for output instead of input.

Defaults to `,` (comma). Overrides `--output-tsv` option.

_
        tags => ['category:output'],
    },
    output_quote_char => {
        summary => 'Specify field quote character in output CSV, will be passed to Text::CSV_XS',
        schema => ['str*', len=>1],
        description => <<'_',

This is like `--quote-char` option but for output instead of input.

Defaults to `"` (double quote). Overrides `--output-tsv` option.

_
        tags => ['category:output'],
    },
    output_escape_char => {
        summary => 'Specify character to escape value in field in output CSV, will be passed to Text::CSV_XS',
        schema => ['str*', len=>1],
        description => <<'_',

This is like `--escape-char` option but for output instead of input.

Defaults to `\\` (backslash). Overrides `--output-tsv` option.

_
        tags => ['category:output'],
    },
);

our %arg_filename_1 = (
    filename => {
        summary => 'Input CSV file',
        description => <<'_',

Use `-` to read from stdin.

_
        schema => 'filename*',
        req => 1,
        pos => 1,
        cmdline_aliases => {f=>{}},
        tags => ['category:input'],
    },
);

our %arg_filename_0 = (
    filename => {
        summary => 'Input CSV file',
        description => <<'_',

Use `-` to read from stdin.

_
        schema => 'filename*',
        req => 1,
        pos => 0,
        cmdline_aliases => {f=>{}},
        tags => ['category:input'],
    },
);

our %arg_filenames_0 = (
    filenames => {
        'x.name.is_plural' => 1,
        summary => 'Input CSV files',
        description => <<'_',

Use `-` to read from stdin.

_
        schema => ['array*', of=>'filename*'],
        req => 1,
        pos => 0,
        slurpy => 1,
        cmdline_aliases => {f=>{}},
        tags => ['category:input'],
    },
);

our %argopt_field = (
    field => {
        summary => 'Field name',
        schema => 'str*',
        cmdline_aliases => { F=>{} },
    },
);

our %arg_field_1 = (
    field => {
        summary => 'Field name',
        schema => 'str*',
        cmdline_aliases => { F=>{} },
        req => 1,
        pos => 1,
        completion => \&_complete_field,
    },
);

our %arg_field_1_nocomp = (
    field => {
        summary => 'Field name',
        schema => 'str*',
        cmdline_aliases => { F=>{} },
        req => 1,
        pos => 1,
    },
);

# let's just use field selection args for consistency
#our %argspecs1_fields = (
#    fields => {
#        'x.name.is_plural' => 1,
#        'x.name.singular' => 'field',
#        summary => 'Field names',
#        schema => ['array*', of=>'str*'],
#        cmdline_aliases => {
#            f => {},
#        },
#        pos => 1,
#        slurpy => 1,
#        element_completion => \&_complete_field,
#        tags => ['category:field-selection'],
#    },
#);

our %argspecsopt_field_selection = (
    include_fields => {
        'x.name.is_plural' => 1,
        'x.name.singular' => 'include_field',
        summary => 'Field names to include, takes precedence over --exclude-field-pat',
        schema => ['array*', of=>'str*'],
        cmdline_aliases => {
            f => {},
            field => {}, # backward compatibility
        },
        element_completion => \&_complete_field,
        tags => ['category:field-selection'],
    },
    include_field_pat => {
        summary => 'Field regex pattern to select, overidden by --exclude-field-pat',
        schema => 're*',
        cmdline_aliases => {
            field_pat => {}, # backward compatibility
            include_all_fields => { summary => 'Shortcut for --field-pat=.*, effectively selecting all fields', is_flag=>1, code => sub { $_[0]{field_pat} = '.*' } },
        },
        tags => ['category:field-selection'],
    },
    exclude_fields => {
        'x.name.is_plural' => 1,
        'x.name.singular' => 'exclude_field',
        summary => 'Field names to exclude, takes precedence over --fields',
        schema => ['array*', of=>'str*'],
        cmdline_aliases => {
            F => {},
        },
        element_completion => \&_complete_field,
        tags => ['category:field-selection'],
    },
    exclude_field_pat => {
        summary => 'Field regex pattern to exclude, takes precedence over --field-pat',
        schema => 're*',
        cmdline_aliases => {
            exclude_all_fields => { summary => 'Shortcut for --field-pat=.*, effectively selecting all fields', is_flag=>1, code => sub { $_[0]{field_pat} = '.*' } },
        },
        tags => ['category:field-selection'],
    },
);

our %arg_eval_1 = (
    eval => {
        summary => 'Perl code to do munging',
        schema => ['any*', of=>['str*', 'code*']],
        cmdline_aliases => { e=>{} },
        req => 1,
        pos => 1,
    },
);

our %arg_eval_2 = (
    eval => {
        summary => 'Perl code to do munging',
        schema => ['any*', of=>['str*', 'code*']],
        cmdline_aliases => { e=>{} },
        req => 1,
        pos => 2,
    },
);

our %args_sort_rows_short = (
    reverse => {
        schema => ['bool', is=>1],
        cmdline_aliases => {r=>{}},
    },
    ci => {
        schema => ['bool', is=>1],
        cmdline_aliases => {i=>{}},
    },
    by_fields => {
        summary => 'Sort by a comma-separated list of field specification',
        description => <<'_',

`+FIELD` to mean sort numerically ascending, `-FIELD` to sort numerically
descending, `FIELD` to mean sort ascibetically ascending, `~FIELD` to mean sort
ascibetically descending.

_
        schema => ['str*'],
        completion => \&_complete_sort_field_list,
    },
    key => {
        summary => 'Generate sort keys with this Perl code',
        description => <<'_',

If specified, then will compute sort keys using Perl code and sort using the
keys. Relevant when sorting using `--by-code` or `--by-sortsub`. If specified,
then instead of rows the code/Sort::Sub routine will receive these sort keys to
sort against.

The code will receive the row as the argument.

_
        schema => ['any*', of=>['str*', 'code*']],
        cmdline_aliases => {k=>{}},
    },
    by_sortsub => {
        schema => 'str*',
        description => <<'_',

Usually combined with `--key` because most Sort::Sub routine expects a string to
be compared against.

_
        summary => 'Sort using a Sort::Sub routine',
        'x.completion' => ['sortsub_spec'],
    },
    sortsub_args => {
        summary => 'Arguments to pass to Sort::Sub routine',
        schema => ['hash*', of=>'str*'],
    },
    by_code => {
        summary => 'Sort using Perl code',
        schema => ['any*', of=>['str*', 'code*']],
        description => <<'_',

`$a` and `$b` (or the first and second argument) will contain the two rows to be
compared. Which are arrayrefs; or if `--hash` (`-H`) is specified, hashrefs; or
if `--key` is specified, whatever the code in `--key` returns.

_
    },
);

our %args_sort_fields = (
    sort_reverse => {
        schema => ['bool', is=>1],
    },
    sort_ci => {
        schema => ['bool', is=>1],
    },
    sort_example => {
        schema => ['array*', of=>'str*',
                   'x.perl.coerce_rules' => ['From_str::comma_sep']],
    },
);

our %args_sort_fields_short = (
    reverse => {
        schema => ['bool', is=>1],
        cmdline_aliases => {r=>{}},
    },
    ci => {
        schema => ['bool', is=>1],
        cmdline_aliases => {i=>{}},
    },
    example => {
        summary => 'A comma-separated list of field names',
        schema => ['str*'],
        completion => \&_complete_field_list,
    },
);

our %arg_with_data_rows = (
    with_data_rows => {
        summary => 'Whether to also output data rows',
        schema => 'bool',
    },
);

our %arg_eval = (
    eval => {
        summary => 'Perl code',
        schema => ['any*', of=>['str*', 'code*']],
        cmdline_aliases => { e=>{} },
        req => 1,
    },
);

our %argopt_eval = (
    eval => {
        summary => 'Perl code to do munging',
        schema => ['any*', of=>['str*', 'code*']],
        cmdline_aliases => { e=>{} },
    },
);

our %arg_hash = (
    hash => {
        summary => 'Provide row in $_ as hashref instead of arrayref',
        schema => ['bool*', is=>1],
        cmdline_aliases => {H=>{}},
    },
);

sub _array2hash {
    my ($row, $fields) = @_;
    my $rowhash = {};
    for my $i (0..$#{$fields}) {
        $rowhash->{ $fields->[$i] } = $row->[$i];
    }
    $rowhash;
}

$SPEC{csvutil} = {
    v => 1.1,
    summary => 'Perform action on a CSV file',
    'x.no_index' => 1,
    args => {
        %args_common,
        action => {
            schema => ['str*', in=>[
                'add-field',
                'list-field-names',
                'info',
                'delete-field',
                'munge-field',
                'munge-row',
                #'replace-newline', # not implemented in csvutil
                'sort-rows',
                'sort-fields',
                'sum',
                'avg',
                'select-row',
                'split',
                'grep',
                'map',
                'each-row',
                'convert-to-hash',
                'convert-to-td',
                #'concat', # not implemented in csvutil
                'select-fields',
                'dump',
                'csv',
                #'setop', # not implemented in csvutil
                #'lookup-fields', # not implemented in csvutil
                'transpose',
                'freqtable',
            ]],
            req => 1,
            pos => 0,
            cmdline_aliases => {a=>{}},
        },
        %arg_filename_1,
        %argopt_eval,
        %argopt_field,
        %argspecsopt_field_selection,
    },
    args_rels => {
    },
};
sub csvutil {
    my %args = @_;
    #use DD; dd \%args;

    my $action = $args{action};
    my $has_header = $args{header} // 1;
    my $outputs_header = $args{output_header} // $has_header;
    my $add_newline = $args{add_newline} // 1;

    my $csv_parser  = _instantiate_parser(\%args);
    my $csv_emitter = _instantiate_emitter(\%args);
    my $fh;
    if ($args{filename} eq '-') {
        $fh = *STDIN;
    } else {
        open $fh, "<", $args{filename} or
            return [500, "Can't open input filename '$args{filename}': $!"];
    }
    binmode $fh, ":encoding(utf8)";

    my $res = "";
    my $i = 0;
    my $header_row_count = 0;
    my $data_row_count = 0;
    my $fields = []; # field names, in order
    my %field_idxs; # key = field name, val = index (0-based)

    my $code;
    my $field_idx;
    my $field_idxs_array;
    my $sorted_fields;
    my @summary_row;
    my $selected_row;
    my $row_spec_sub;
    my %freqtable; # key=value, val=frequency

    # for action=split
    my ($split_fh, $split_filename, $split_lines);

    my $row0;
    my $code_getline = sub {
        if ($i == 0 && !$has_header) {
            $row0 = $csv_parser->getline($fh);
            return unless $row0;
            return [map { "field$_" } 1..@$row0];
        } elsif ($i == 1 && !$has_header) {
            $header_row_count++;
            return $row0;
        }
        $data_row_count++;
        $csv_parser->getline($fh);
    };

    my $rows = [];

    while (my $row = $code_getline->()) {
        #use DD; dd $row;
        $i++;
        if ($i == 1) {
            # header row

            $fields = $row;
            for my $j (0..$#{$row}) {
                unless (length $row->[$j]) {
                    #return [412, "Empty field name in field #$j"];
                    next;
                }
                if (defined $field_idxs{$row->[$j]}) {
                    return [412, "Duplicate field name '$row->[$j]'"];
                }
                $field_idxs{$row->[$j]} = $j;
            }
            if ($action eq 'sort-fields') {
                if (my $eg = $args{sort_example}) {
                    $eg = [split /\s*,\s*/, $eg] unless ref($eg) eq 'ARRAY';
                    require Sort::ByExample;
                    my $sorter = Sort::ByExample::sbe($eg);
                    $sorted_fields = [$sorter->(@$row)];
                } else {
                    # alphabetical
                    if ($args{sort_ci}) {
                        $sorted_fields = [sort {lc($a) cmp lc($b)} @$row];
                    } else {
                        $sorted_fields = [sort {$a cmp $b} @$row];
                    }
                }
                $sorted_fields = [reverse @$sorted_fields]
                    if $args{sort_reverse};
                $row = $sorted_fields;
            }
            if ($action eq 'sum' || $action eq 'avg') {
                @summary_row = map {0} @$row;
            }
            if ($action eq 'select-row') {
                my $spec = $args{row_spec};
                my @codestr;
                for my $spec_item (split /\s*,\s*/, $spec) {
                    if ($spec_item =~ /\A\d+\z/) {
                        push @codestr, "(\$i == $spec_item)";
                    } elsif ($spec_item =~ /\A(\d+)\s*-\s*(\d+)\z/) {
                        push @codestr, "(\$i >= $1 && \$i <= $2)";
                    } else {
                        return [400, "Invalid row specification '$spec_item'"];
                    }
                }
                $row_spec_sub = eval 'sub { my $i = shift; '.join(" || ", @codestr).' }'; ## no critic: BuiltinFunctions::ProhibitStringyEval
                return [400, "BUG: Invalid row_spec code: $@"] if $@;
            }
            if ($action eq 'grep') {
            } elsif ($action eq 'map') {
            } elsif ($action eq 'sort-rows') {
            } elsif ($action eq 'each-row') {
            } elsif ($action eq 'csv') {
            } elsif ($action eq 'transpose') {
            }
        } # if i==1 (header row)

        if ($action eq 'list-field-names') {
            return [200, "OK",
                    [map { {name=>$_, index=>$field_idxs{$_}+1} }
                         sort keys %field_idxs],
                    {'table.fields'=>['name','index']}];
        } elsif ($action eq 'info') {
        } elsif ($action eq 'munge-field') {
            unless ($i == 1) {
                unless ($code) {
                    $code = _compile($args{eval});
                    $field_idx = _get_field_idx($args{field}, \%field_idxs);
                }
                if (defined $row->[$field_idx]) {
                    local $_ = $row->[$field_idx];
                    local $main::row = $row;
                    local $main::rownum = $i;
                    local $main::csv = $csv_parser;
                    local $main::field_idxs = \%field_idxs;
                    eval { $code->($_) };
                    die "Error while munging row ".
                        "#$i field '$args{field}' value '$_': $@\n" if $@;
                    $row->[$field_idx] = $_;
                }
            }
            $res .= _get_csv_row($csv_emitter, $row, $i, $outputs_header);
        } elsif ($action eq 'munge-row') {
            unless ($i == 1) {
                unless ($code) {
                    $code = _compile($args{eval});
                }
                local $_ = $args{hash} ? _array2hash($row, $fields) : $row;
                local $main::row = $row;
                local $main::rownum = $i;
                local $main::csv = $csv_parser;
                local $main::field_idxs = \%field_idxs;
                eval { $code->($_) };
                die "Error while munging row ".
                    "#$i field '$args{field}' value '$_': $@\n" if $@;
                if ($args{hash}) {
                    for my $field (keys %$_) {
                        $row->[$field_idxs{$field}] = $_->{$field};
                    }
                }
            }
            $res .= _get_csv_row($csv_emitter, $row, $i, $outputs_header);
        } elsif ($action eq 'add-field') {
            if ($i == 1) {
                if (defined $args{_at}) {
                    $field_idx = $args{_at}-1;
                } elsif (defined $args{before}) {
                    for (0..$#{$row}) {
                        if ($row->[$_] eq $args{before}) {
                            $field_idx = $_;
                            last;
                        }
                    }
                    return [400, "Field '$args{before}' not found"]
                        unless defined $field_idx;
                } elsif (defined $args{after}) {
                    for (0..$#{$row}) {
                        if ($row->[$_] eq $args{after}) {
                            $field_idx = $_+1;
                            last;
                        }
                    }
                    return [400, "Field '$args{after}' not found"]
                        unless defined $field_idx;
                } else {
                    $field_idx = @$row;
                }
                splice @$row, $field_idx, 0, $args{field};
                for (keys %field_idxs) {
                    if ($field_idxs{$_} >= $field_idx) {
                        $field_idxs{$_}++;
                    }
                }
                $fields = $row;
            } else {
                unless ($code) {
                    $code = _compile($args{eval});
                    if (!defined($args{field}) || !length($args{field})) {
                        return [400, "Please specify field (-F)"];
                    }
                    if (defined $field_idxs{$args{field}}) {
                        return [412, "Field '$args{field}' already exists"];
                    }
                }
                {
                    local $_;
                    local $main::row = $row;
                    local $main::rownum = $i;
                    local $main::csv = $csv_parser;
                    local $main::field_idxs = \%field_idxs;
                    eval { $_ = $code->() };
                    die "Error while adding field '$args{field}' for row #$i: $@\n"
                        if $@;
                    splice @$row, $field_idx, 0, $_;
                }
            }
            $res .= _get_csv_row($csv_emitter, $row, $i, $outputs_header);
        } elsif ($action eq 'delete-field') {
            if (!defined($field_idxs_array)) {
                $field_idxs_array = [];
                for my $f (@{ $args{_fields} }) {
                    push @$field_idxs_array, _get_field_idx($f, \%field_idxs);
                }
                $field_idxs_array = [sort {$b<=>$a} @$field_idxs_array];
                for (@$field_idxs_array) {
                    splice @$row, $_, 1;
                    unless (@$row) {
                        return [412, "Can't delete field(s) because CSV will have zero fields"];
                    }
                }
            } else {
                for (@$field_idxs_array) {
                    splice @$row, $_, 1;
                }
            }
            $res .= _get_csv_row($csv_emitter, $row, $i, $outputs_header);
        } elsif ($action eq 'select-fields') {
            if (!defined($field_idxs_array)) {
                $field_idxs_array = [];
                my %seen;
                if ($args{_fields}) {
                    for my $f (@{ $args{_fields} }) {
                        return [400, "Duplicate field '$f'"] if $seen{$f}++;
                        push @$field_idxs_array, _get_field_idx($f, \%field_idxs);
                    }
                } else {
                    for my $f (@$fields) {
                        next unless $f =~ $args{_field_pat};
                        push @$field_idxs_array, $field_idxs{$f};
                    }
                }
            }
            $row = [map { $row->[$_] } @$field_idxs_array];
            $res .= _get_csv_row($csv_emitter, $row, $i, $outputs_header);
        } elsif ($action eq 'sort-fields') {
            unless ($i == 1) {
                my @new_row;
                for (@$sorted_fields) {
                    push @new_row, $row->[$field_idxs{$_}];
                }
                $row = \@new_row;
            }
            $res .= _get_csv_row($csv_emitter, $row, $i, $outputs_header);
        } elsif ($action eq 'sum') {
            if ($i == 1) {
                $res .= _get_csv_row($csv_emitter, $row, $i, $outputs_header);
            } else {
                require Scalar::Util;
                for (0..$#{$row}) {
                    next unless Scalar::Util::looks_like_number($row->[$_]);
                    $summary_row[$_] += $row->[$_];
                }
                $res .= _get_csv_row($csv_emitter, $row, $i, $outputs_header)
                    if $args{_with_data_rows};
            }
        } elsif ($action eq 'avg') {
            if ($i == 1) {
                $res .= _get_csv_row($csv_emitter, $row, $i, $outputs_header);
            } else {
                require Scalar::Util;
                for (0..$#{$row}) {
                    next unless Scalar::Util::looks_like_number($row->[$_]);
                    $summary_row[$_] += $row->[$_];
                }
                $res .= _get_csv_row($csv_emitter, $row, $i, $outputs_header)
                    if $args{_with_data_rows};
            }
        } elsif ($action eq 'freqtable') {
            if ($i == 1) {
            } else {
                $field_idx = _get_field_idx($args{field}, \%field_idxs);
                $freqtable{ $row->[$field_idx] }++;
            }
        } elsif ($action eq 'select-row') {
            if ($i == 1 || $row_spec_sub->($i)) {
                $res .= _get_csv_row($csv_emitter, $row, $i, $outputs_header);
            }
        } elsif ($action eq 'split') {
            next if $i == 1;
            unless (defined $split_fh) {
                $split_filename = "xaa";
                $split_lines = 0;
                open $split_fh, ">", $split_filename
                    or die "Can't open '$split_filename': $!\n";
            }
            if ($split_lines >= $args{lines}) {
                $split_filename++;
                $split_lines = 0;
                open $split_fh, ">", $split_filename
                    or die "Can't open '$split_filename': $!\n";
            }
            if ($split_lines == 0 && $has_header) {
                $csv_emitter->print($split_fh, $fields);
                print $split_fh "\n";
            }
            $csv_emitter->print($split_fh, $row);
            print $split_fh "\n";
            $split_lines++;
        } elsif ($action eq 'grep') {
            unless ($code) {
                $code = _compile($args{eval});
            }
            if ($i == 1 || do {
                local $_ = $args{hash} ? _array2hash($row, $fields) : $row;
                local $main::row = $row;
                local $main::rownum = $i;
                local $main::csv = $csv_parser;
                local $main::field_idxs = \%field_idxs;
                $code->($row);
            }) {
                $res .= _get_csv_row($csv_emitter, $row, $i, $outputs_header);
            }
        } elsif ($action eq 'map' || $action eq 'each-row') {
            unless ($code) {
                $code = _compile($args{eval});
            }
            if ($i > 1) {
                my $rowres = do {
                    local $_ = $args{hash} ? _array2hash($row, $fields) : $row;
                    local $main::row = $row;
                    local $main::rownum = $i;
                    local $main::csv = $csv_parser;
                    local $main::field_idxs = \%field_idxs;
                    $code->($row);
                } // '';
                if ($action eq 'map') {
                    unless (!$add_newline || $rowres =~ /\R\z/) {
                        $rowres .= "\n";
                    }
                    $res .= $rowres;
                }
            }
        } elsif ($action eq 'sort-rows') {
            push @$rows, $row unless $i == 1;
        } elsif ($action eq 'transpose') {
            push @$rows, $row;
        } elsif ($action eq 'convert-to-hash') {
            if ($i == $args{_row_number}) {
                $selected_row = $row;
            }
        } elsif ($action eq 'convert-to-td') {
            push @$rows, $row unless $i == 1;
        } elsif ($action eq 'dump') {
            if ($args{hash}) {
                push @$rows, _array2hash($row, $fields) unless $i == 1;
            } else {
                push @$rows, $row;
            }
        } elsif ($action eq 'csv') {
            $res .= _get_csv_row($csv_emitter, $row, $i, $outputs_header);
        } else {
            return [400, "Unknown action '$action'"];
        }
    } # while getline()

    if ($action eq 'info') {
        return [200, "OK", {
            field_count => scalar @$fields,
            fields      => $fields,

            row_count        => $header_row_count + $data_row_count,
            header_row_count => $header_row_count,
            data_row_count   => $data_row_count,

            #file_size  => $chars, # we use csv's getline() so how?
            file_size   => (-s $fh),
        }];
    }

    if ($action eq 'convert-to-hash') {
        $selected_row //= [];
        my $hash = {};
        for (0..$#{$fields}) {
            $hash->{ $fields->[$_] } = $selected_row->[$_];
        }
        return [200, "OK", $hash];
    }

    if ($action eq 'convert-to-td') {
        return [200, "OK", $rows, {'table.fields'=>$fields}];
    }

    if ($action eq 'sum') {
        $res .= _get_csv_row($csv_emitter, \@summary_row,
                             $args{_with_data_rows} ? $i+1 : 2,
                             $outputs_header);
    } elsif ($action eq 'avg') {
        if ($i > 2) {
            for (@summary_row) { $_ /= ($i-1) }
        }
        $res .= _get_csv_row($csv_emitter, \@summary_row,
                             $args{_with_data_rows} ? $i+1 : 2,
                             $outputs_header);
    }

    if ($action eq 'freqtable') {
        my @freqtable;
        for (sort { $freqtable{$b} <=> $freqtable{$a} } keys %freqtable) {
            push @freqtable, [$_, $freqtable{$_}];
        }
        return [200, "OK", \@freqtable, {'table.fields'=>['value','freq']}];
    }

    if ($action eq 'dump') {
        return [200, "OK", $rows];
    }

    if ($action eq 'sort-rows') {

        # whether we should compute keys
        my @keys;
        if ($args{sort_key}) {
            my $code_gen_key = _compile($args{sort_key});
            for my $row (@$rows) {
                local $_ = $args{hash} ? _array2hash($row, $fields) : $row;
                push @keys, $code_gen_key->($_);
            }
        }

        if ($args{sort_by_code} || $args{sort_by_sortsub}) {
            my $code0;
            if ($args{sort_by_code}) {
                $code0 = _compile($args{sort_by_code});
            } elsif (defined $args{sort_by_sortsub}) {
                require Sort::Sub;
                $code0 = Sort::Sub::get_sorter(
                    $args{sort_by_sortsub}, $args{sort_sortsub_args});
            }

            if (@keys) {
                # compare two sort keys ($a & $b) are indices
                $code = sub {
                    local $main::a = $keys[$a];
                    local $main::b = $keys[$b];
                    $code0->($main::a, $main::b);
                };
            } elsif ($args{hash}) {
                # compare two rowhashes
                $code = sub {
                    local $main::a = _array2hash($a, $fields);
                    local $main::b = _array2hash($b, $fields);
                    $code0->($main::a, $main::b);
                };
            } else {
                # compare two arrayref rows
                $code = $code0;
            }

            if (@keys) {
                # sort indices according to keys first, then return sorted rows
                # according to indices
                my @sorted_indices = sort { local $main::a=$a; local $main::b=$b; $code->($main::a,$main::b) } 0..$#{$rows};
                $rows = [map {$rows->[$_]} @sorted_indices];
            } else {
                $rows = [sort { local $main::a=$a; local $main::b=$b; $code->($main::a,$main::b) } @$rows];
            }
        } elsif ($args{sort_by_fields}) {
            my @fields;
            my $code_str = "";
            for my $field_spec (split /,/, $args{sort_by_fields}) {
                my ($prefix, $field) = $field_spec =~ /\A([+~-]?)(.+)/;
                my $field_idx = $field_idxs{$field};
                return [400, "Unknown field '$field' (known fields include: ".
                            join(", ", map { "'$_'" } sort {$field_idxs{$a} <=> $field_idxs{$b}}
                                 keys %field_idxs).")"] unless defined $field_idx;
                $prefix //= "";
                if ($prefix eq '+') {
                    $code_str .= ($code_str ? " || " : "") .
                        "(\$a->[$field_idx] <=> \$b->[$field_idx])";
                } elsif ($prefix eq '-') {
                    $code_str .= ($code_str ? " || " : "") .
                        "(\$b->[$field_idx] <=> \$a->[$field_idx])";
                } elsif ($prefix eq '') {
                    if ($args{sort_ci}) {
                        $code_str .= ($code_str ? " || " : "") .
                            "(lc(\$a->[$field_idx]) cmp lc(\$b->[$field_idx]))";
                    } else {
                        $code_str .= ($code_str ? " || " : "") .
                            "(\$a->[$field_idx] cmp \$b->[$field_idx])";
                    }
                } elsif ($prefix eq '~') {
                    if ($args{sort_ci}) {
                        $code_str .= ($code_str ? " || " : "") .
                            "(lc(\$b->[$field_idx]) cmp lc(\$a->[$field_idx]))";
                    } else {
                        $code_str .= ($code_str ? " || " : "") .
                            "(\$b->[$field_idx] cmp \$a->[$field_idx])";
                    }
                }
            }
            $code = _compile($code_str);
            $rows = [sort { local $main::a = $a; local $main::b = $b; $code->($main::a, $main::b) } @$rows];
        } else {
            return [400, "Please specify by_fields or by_sortsub or by_code"];
        }

        if ($has_header) {
            $csv_emitter->combine(@$fields);
            $res .= $csv_emitter->string . "\n";
        }
        for my $row (@$rows) {
            $res .= _get_csv_row($csv_emitter, $row, $i, $outputs_header);
        }
    }

    if ($action eq 'transpose') {
        my $transposed_rows = [];
        for my $rownum (0..$#{$rows}) {
            for my $colnum (0..$#{$fields}) {
                $transposed_rows->[$colnum][$rownum] =
                    $rows->[$rownum][$colnum];
            }
        }
        for my $rownum (0..$#{$transposed_rows}) {
            $res .= _get_csv_row($csv_emitter, $transposed_rows->[$rownum],
                                 $rownum+1, $outputs_header);
        }
    }

    [200, "OK", $res, {"cmdline.skip_format"=>1}];
} # csvutil

our $common_desc = <<'_';
*Common notes for the utilities*

Encoding: The utilities in this module/distribution accept and emit UTF8 text.

_

$SPEC{csv_add_field} = {
    v => 1.1,
    summary => 'Add a field to CSV file',
    description => <<'_' . $common_desc,

Your Perl code (-e) will be called for each row (excluding the header row) and
should return the value for the new field. `$main::row` is available and
contains the current row. `$main::rownum` contains the row number (2 means the
first data row). `$csv` is the <pm:Text::CSV_XS> object. `$main::field_idxs` is
also available for additional information.

Field by default will be added as the last field, unless you specify one of
`--after` (to put after a certain field), `--before` (to put before a certain
field), or `--at` (to put at specific position, 1 means as the first field).

_
    args => {
        %args_common,
        %args_csv_output,
        %arg_filename_0,
        %arg_field_1_nocomp,
        %arg_eval_2,
        after => {
            summary => 'Put the new field after specified field',
            schema => 'str*',
            completion => \&_complete_field,
        },
        before => {
            summary => 'Put the new field before specified field',
            schema => 'str*',
            completion => \&_complete_field,
        },
        at => {
            summary => 'Put the new field at specific position '.
                '(1 means as first field)',
            schema => ['int*', min=>1],
        },
    },
    args_rels => {
        choose_one => [qw/after before at/],
    },
    tags => ['outputs_csv'],
};
sub csv_add_field {
    my %args = @_;
    csvutil(
        %args, action=>'add-field',
        _after  => $args{after},
        _before => $args{before},
        _at     => $args{at},
    );
}

$SPEC{csv_list_field_names} = {
    v => 1.1,
    summary => 'List field names of CSV file',
    args => {
        %args_common,
        %arg_filename_0,
    },
    description => '' . $common_desc,
};
sub csv_list_field_names {
    my %args = @_;
    csvutil(%args, action=>'list-field-names');
}

$SPEC{csv_info} = {
    v => 1.1,
    summary => 'Show information about CSV file (number of rows, fields, etc)',
    args => {
        %args_common,
        %arg_filename_0,
    },
    description => '' . $common_desc,
};
sub csv_info {
    my %args = @_;
    csvutil(%args, action=>'info');
}

$SPEC{csv_delete_fields} = {
    v => 1.1,
    summary => 'Delete one or more fields from CSV file',
    args => {
        %args_common,
        %args_csv_output,
        %arg_filename_0,
        %argspecs_field_selection,
    },
    description => '' . $common_desc,
    tags => ['outputs_csv'],
};
sub csv_delete_field {
    my %args = @_;
    csvutil(%args, action=>'delete-field');
}

$SPEC{csv_munge_field} = {
    v => 1.1,
    summary => 'Munge a field in every row of CSV file with Perl code',
    description => <<'_' . $common_desc,

Perl code (-e) will be called for each row (excluding the header row) and `$_`
will contain the value of the field, and the Perl code is expected to modify it.
`$main::row` will contain the current row array. `$main::rownum` contains the
row number (2 means the first data row). `$main::csv` is the <pm:Text::CSV_XS>
object. `$main::field_idxs` is also available for additional information.

_
    args => {
        %args_common,
        %args_csv_output,
        %arg_filename_0,
        %arg_field_1,
        %arg_eval_2,
    },
    tags => ['outputs_csv'],
};
sub csv_munge_field {
    my %args = @_;
    csvutil(%args, action=>'munge-field');
}

$SPEC{csv_munge_row} = {
    v => 1.1,
    summary => 'Munge each data arow of CSV file with Perl code',
    description => <<'_' . $common_desc,

Perl code (-e) will be called for each row (excluding the header row) and `$_`
will contain the row (arrayref, or hashref if `-H` is specified). The Perl code
is expected to modify it.

Aside from `$_`, `$main::row` will contain the current row array.
`$main::rownum` contains the row number (2 means the first data row).
`$main::csv` is the <pm:Text::CSV_XS> object. `$main::field_idxs` is also
available for additional information.

The modified `$_` will be rendered back to CSV row.

_
    args => {
        %args_common,
        %args_csv_output,
        %arg_filename_0,
        %arg_eval_1,
        %arg_hash,
    },
    tags => ['outputs_csv'],
};
sub csv_munge_row {
    my %args = @_;
    csvutil(%args, action=>'munge-row');
}

$SPEC{csv_replace_newline} = {
    v => 1.1,
    summary => 'Replace newlines in CSV values',
    description => <<'_' . $common_desc,

Some CSV parsers or applications cannot handle multiline CSV values. This
utility can be used to convert the newline to something else. There are a few
choices: replace newline with space (`--with-space`, the default), remove
newline (`--with-nothing`), replace with encoded representation
(`--with-backslash-n`), or with characters of your choice (`--with 'blah'`).

_
    args => {
        %args_common,
        %args_csv_output,
        %arg_filename_0,
        with => {
            schema => 'str*',
            default => ' ',
            cmdline_aliases => {
                with_space => { is_flag=>1, code=>sub { $_[0]{with} = ' ' } },
                with_nothing => { is_flag=>1, code=>sub { $_[0]{with} = '' } },
                with_backslash_n => { is_flag=>1, code=>sub { $_[0]{with} = "\\n" } },
            },
        },
    },
    tags => ['outputs_csv'],
};
sub csv_replace_newline {
    my %args = @_;
    my $with = $args{with};

    my $csv_parser  = _instantiate_parser(\%args);
    my $csv_emitter = _instantiate_emitter(\%args);
    my $fh;
    if ($args{filename} eq '-') {
        $fh = *STDIN;
    } else {
        open $fh, "<", $args{filename} or
            return [500, "Can't open input filename '$args{filename}': $!"];
    }
    binmode $fh, ":encoding(utf8)";

    my $res = "";
    my $i = 0;
    while (my $row = $csv_parser->getline($fh)) {
        $i++;
        for my $col (@$row) {
            $col =~ s/[\015\012]+/$with/g;
        }
        my $status = $csv_emitter->combine(@$row)
            or die "Error in line $i: ".$csv_emitter->error_input;
        $res .= $csv_emitter->string . "\n";
    }

    [200, "OK", $res, {"cmdline.skip_format"=>1}];
}

$SPEC{csv_sort_rows} = {
    v => 1.1,
    summary => 'Sort CSV rows',
    description => <<'_' . $common_desc,

This utility sorts the rows in the CSV. Example input CSV:

    name,age
    Andy,20
    Dennis,15
    Ben,30
    Jerry,30

Example output CSV (using `--by-fields +age` which means by age numerically and
ascending):

    name,age
    Dennis,15
    Andy,20
    Ben,30
    Jerry,30

Example output CSV (using `--by-fields -age`, which means by age numerically and
descending):

    name,age
    Ben,30
    Jerry,30
    Andy,20
    Dennis,15

Example output CSV (using `--by-fields name`, which means by name ascibetically
and ascending):

    name,age
    Andy,20
    Ben,30
    Dennis,15
    Jerry,30

Example output CSV (using `--by-fields ~name`, which means by name ascibetically
and descending):

    name,age
    Jerry,30
    Dennis,15
    Ben,30
    Andy,20

Example output CSV (using `--by-fields +age,~name`):

    name,age
    Dennis,15
    Andy,20
    Jerry,30
    Ben,30

You can also reverse the sort order (`-r`) or sort case-insensitively (`-i`).

For more flexibility, instead of `--by-fields` you can use `--by-code`:

Example output `--by-code '$a->[1] <=> $b->[1] || $b->[0] cmp $a->[0]'` (which
is equivalent to `--by-fields +age,~name`):

    name,age
    Dennis,15
    Andy,20
    Jerry,30
    Ben,30

If you use `--hash`, your code will receive the rows to be compared as hashref,
e.g. `--hash --by-code '$a->{age} <=> $b->{age} || $b->{name} cmp $a->{name}'.

A third alternative is to sort using <pm:Sort::Sub> routines. Example output
(using `--by-sortsub 'by_length<r>' --key '$_->[0]'`, which is to say to sort by
descending length of name):

    name,age
    Dennis,15
    Jerry,30
    Andy,20
    Ben,30

_
    args => {
        %args_common,
        %args_csv_output,
        %arg_filename_0,
        %args_sort_rows_short,
        %arg_hash,
    },
    args_rels => {
        req_one => ['by_fields', 'by_code', 'by_sortsub'],
    },
    tags => ['outputs_csv'],
};
sub csv_sort_rows {
    my %args = @_;

    my %csvutil_args = (
        hash_subset(\%args, \%args_common, \%args_csv_output),
        filename => $args{filename},
        action => 'sort-rows',
        sort_reverse => $args{reverse},
        sort_ci => $args{ci},
        sort_key => $args{key},
        sort_by_fields => $args{by_fields},
        sort_by_code   => $args{by_code},
        sort_by_sortsub => $args{by_sortsub},
        sort_sortsub_args => $args{sortsub_args},
        hash => $args{hash},
    );

    csvutil(%csvutil_args);
}

$SPEC{csv_sort_fields} = {
    v => 1.1,
    summary => 'Sort CSV fields',
    description => <<'_' . $common_desc,

This utility sorts the order of fields in the CSV. Example input CSV:

    b,c,a
    1,2,3
    4,5,6

Example output CSV:

    a,b,c
    3,1,2
    6,4,5

You can also reverse the sort order (`-r`), sort case-insensitively (`-i`), or
provides the ordering, e.g. `--example a,c,b`.

_
    args => {
        %args_common,
        %args_csv_output,
        %arg_filename_0,
        %args_sort_fields_short,
    },
    tags => ['outputs_csv'],
};
sub csv_sort_fields {
    my %args = @_;

    my %csvutil_args = (
        hash_subset(\%args, \%args_common, \%args_csv_output),
        filename => $args{filename},
        action => 'sort-fields',
        (sort_example => $args{example}) x !!defined($args{example}),
        sort_reverse => $args{reverse},
        sort_ci => $args{ci},
    );

    csvutil(%csvutil_args);
}

$SPEC{csv_sum} = {
    v => 1.1,
    summary => 'Output a summary row which are arithmetic sums of data rows',
    args => {
        %args_common,
        %args_csv_output,
        %arg_filename_0,
        %arg_with_data_rows,
    },
    description => '' . $common_desc,
    tags => ['outputs_csv'],
};
sub csv_sum {
    my %args = @_;

    csvutil(%args, action=>'sum', _with_data_rows=>$args{with_data_rows});
}

$SPEC{csv_avg} = {
    v => 1.1,
    summary => 'Output a summary row which are arithmetic averages of data rows',
    args => {
        %args_common,
        %args_csv_output,
        %arg_filename_0,
        %arg_with_data_rows,
    },
    description => '' . $common_desc,
    tags => ['outputs_csv'],
};
sub csv_avg {
    my %args = @_;

    csvutil(%args, action=>'avg', _with_data_rows=>$args{with_data_rows});
}

$SPEC{csv_freqtable} = {
    v => 1.1,
    summary => 'Output a frequency table of values of a specified field in CSV',
    args => {
        %args_common,
        %arg_filename_0,
        %arg_field_1,
    },
    description => '' . $common_desc,
};
sub csv_freqtable {
    my %args = @_;

    csvutil(%args, action=>'freqtable');
}

$SPEC{csv_select_row} = {
    v => 1.1,
    summary => 'Only output specified row(s)',
    args => {
        %args_common,
        %args_csv_output,
        %arg_filename_0,
        row_spec => {
            schema => 'str*',
            summary => 'Row number (e.g. 2 for first data row), '.
                'range (2-7), or comma-separated list of such (2-7,10,20-23)',
            req => 1,
            pos => 1,
        },
    },
    description => '' . $common_desc,
    links => [
        {url=>"prog:csv-split"},
    ],
    tags => ['outputs_csv'],
};
sub csv_select_row {
    my %args = @_;

    csvutil(%args, action=>'select-row');
}

$SPEC{csv_split} = {
    v => 1.1,
    summary => 'Split CSV file into several files',
    description => <<'_' . $common_desc,

Will output split files xaa, xab, and so on. Each split file will contain a
maximum of `lines` rows (options to limit split files' size based on number of
characters and bytes will be added). Each split file will also contain CSV
header.

Warning: by default, existing split files xaa, xab, and so on will be
overwritten.

Interface is loosely based on the `split` Unix utility.

_
    args => {
        %args_common,
        %args_csv_output,
        %arg_filename_0,
        lines => {
            schema => ['uint*', min=>1],
            default => 1000,
            cmdline_aliases => {l=>{}},
        },
        # XXX --bytes (-b)
        # XXX --line-bytes (-C)
        # XXX -d (numeric suffix)
        # --suffix-length (-a)
        # --number, -n (chunks)
    },
    links => [
        {url=>"prog:csv-select-row"},
    ],
    tags => ['outputs_csv'],
};
sub csv_split {
    my %args = @_;

    csvutil(%args, action=>'split');
}

$SPEC{csv_grep} = {
    v => 1.1,
    summary => 'Only output row(s) where Perl expression returns true',
    description => <<'_' . $common_desc,

This is like Perl's `grep` performed over rows of CSV. In `$_`, your Perl code
will find the CSV row as an arrayref (or, if you specify `-H`, as a hashref).
`$main::row` is also set to the row (always as arrayref). `$main::rownum`
contains the row number (2 means the first data row). `$main::csv` is the
<pm:Text::CSV_XS> object. `$main::field_idxs` is also available for additional
information.

Your code is then free to return true or false based on some criteria. Only rows
where Perl expression returns true will be included in the result.

_
    args => {
        %args_common,
        %args_csv_output,
        %arg_filename_0,
        %arg_eval,
        %arg_hash,
    },
    examples => [
        {
            summary => 'Only show rows where the amount field '.
                'is divisible by 7',
            argv => ['-He', '$_->{amount} % 7 ? 1:0', 'file.csv'],
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'Only show rows where date is a Wednesday',
            argv => ['-He', 'BEGIN { use DateTime::Format::Natural; $parser = DateTime::Format::Natural->new } $dt = $parser->parse_datetime($_->{date}); $dt->day_of_week == 3', 'file.csv'],
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],
    links => [
        {url=>'prog:csvgrep'},
    ],
    tags => ['outputs_csv'],
};
sub csv_grep {
    my %args = @_;

    csvutil(%args, action=>'grep');
}

$SPEC{csv_map} = {
    v => 1.1,
    summary => 'Return result of Perl code for every row',
    description => <<'_' . $common_desc,

This is like Perl's `map` performed over rows of CSV. In `$_`, your Perl code
will find the CSV row as an arrayref (or, if you specify `-H`, as a hashref).
`$main::row` is also set to the row (always as arrayref). `$main::rownum`
contains the row number (2 means the first data row). `$main::csv` is the
<pm:Text::CSV_XS> object. `$main::field_idxs` is also available for additional
information.

Your code is then free to return a string based on some operation against these
data. This utility will then print out the resulting string.

_
    args => {
        %args_common,
        %arg_filename_0,
        %arg_eval,
        %arg_hash,
        add_newline => {
            summary => 'Whether to make sure each string ends with newline',
            schema => 'bool*',
            default => 1,
        },
    },
    examples => [
        {
            summary => 'Create SQL insert statements (escaping is left as an exercise for users)',
            argv => ['-He', '"INSERT INTO mytable (id,amount) VALUES ($_->{id}, $_->{amount});"', 'file.csv'],
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],
    links => [
        {url=>'prog:csvgrep'},
    ],
};
sub csv_map {
    my %args = @_;

    csvutil(%args, action=>'map');
}

$SPEC{csv_each_row} = {
    v => 1.1,
    summary => 'Run Perl code for every row',
    description => <<'_' . $common_desc,

This is like csv_map, except result of code is not printed.

_
    args => {
        %args_common,
        %arg_filename_0,
        %arg_eval,
        %arg_hash,
    },
    examples => [
        {
            summary => 'Delete user data',
            argv => ['-He', '"unlink qq(/home/data/$_->{username}.dat)"', 'users.csv'],
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],
    links => [
    ],
};
sub csv_each_row {
    my %args = @_;

    csvutil(%args, action=>'each-row');
}

$SPEC{csv_convert_to_hash} = {
    v => 1.1,
    summary => 'Return a hash of field names as keys and first row as values',
    args => {
        %args_common,
        %arg_filename_0,
        row_number => {
            schema => ['int*', min=>2],
            default => 2,
            summary => 'Row number (e.g. 2 for first data row)',
            pos => 1,
        },
    },
    description => '' . $common_desc,
};
sub csv_convert_to_hash {
    my %args = @_;

    csvutil(%args, action=>'convert-to-hash',
            _row_number=>$args{row_number} // 2);
}

$SPEC{csv_transpose} = {
    v => 1.1,
    summary => 'Transpose a CSV',
    args => {
        %args_common,
        %args_csv_output,
        %arg_filename_0,
    },
    description => '' . $common_desc,
    tags => ['outputs_csv'],
};
sub csv_transpose {
    my %args = @_;

    csvutil(%args, action=>'transpose');
}

$SPEC{csv2td} = {
    v => 1.1,
    summary => 'Return an enveloped aoaos table data from CSV data',
    description => <<'_',

Read more about "table data" in <pm:App::td>, which comes with a CLI <prog:td>
to munge table data.

_
    args => {
        %args_common,
        %arg_filename_0,
    },
    description => '' . $common_desc,
};
sub csv2td {
    my %args = @_;

    csvutil(%args, action=>'convert-to-td');
}

$SPEC{csv_concat} = {
    v => 1.1,
    summary => 'Concatenate several CSV files together, '.
        'collecting all the fields',
    description => <<'_' . $common_desc,

Example, concatenating this CSV:

    col1,col2
    1,2
    3,4

and:

    col2,col4
    a,b
    c,d
    e,f

and:

    col3
    X
    Y

will result in:

    col1,col2,col4,col3
    1,2,
    3,4,
    ,a,b
    ,c,d
    ,e,f
    ,,,X
    ,,,Y

_
    args => {
        %args_common,
        %args_csv_output,
        %arg_filenames_0,
    },
    tags => ['outputs_csv'],
};
sub csv_concat {
    my %args = @_;

    my %res_field_idxs;
    my @rows;

    for my $filename (@{ $args{filenames} }) {
        my $csv_parser  = _instantiate_parser(\%args);
        my $fh;
        if ($filename eq '-') {
            $fh = *STDIN;
        } else {
            open $fh, "<", $filename or
            return [500, "Can't open input filename '$filename': $!"];
        }
        binmode $fh, ":encoding(utf8)";

        my $i = 0;
        my $fields;
        while (my $row = $csv_parser->getline($fh)) {
            $i++;
            if ($i == 1) {
                $fields = $row;
                for my $field (@$fields) {
                    unless (exists $res_field_idxs{$field}) {
                        $res_field_idxs{$field} = keys(%res_field_idxs);
                    }
                }
                next;
            }
            my $res_row = [];
            for my $j (0..$#{$row}) {
                my $field = $fields->[$j];
                $res_row->[ $res_field_idxs{$field} ] = $row->[$j];
            }
            push @rows, $res_row;
        }
    } # for each filename

    my $num_fields = keys %res_field_idxs;
    my $res = "";
    my $csv_emitter = _instantiate_emitter(\%args);

    # generate header
    my $status = $csv_emitter->combine(
        sort { $res_field_idxs{$a} <=> $res_field_idxs{$b} }
            keys %res_field_idxs)
        or die "Error in generating result header row: ".$csv_emitter->error_input;
    $res .= $csv_emitter->string . "\n";
    for my $i (0..$#rows) {
        my $row = $rows[$i];
        $row->[$num_fields-1] = undef if @$row < $num_fields;
        my $status = $csv_emitter->combine(@$row)
            or die "Error in generating data row #".($i+1).": ".
            $csv_emitter->error_input;
        $res .= $csv_emitter->string . "\n";
    }
    [200, "OK", $res, {"cmdline.skip_format"=>1}];
}

$SPEC{csv_select_fields} = {
    v => 1.1,
    summary => 'Only output selected field(s)',
    args => {
        %args_common,
        %args_csv_output,
        %arg_filename_0,
        %argspecs_field_selection,
    },
    args_rels => {
        req_one => ['fields', 'field_pat'],
    },
    description => '' . $common_desc,
    tags => ['outputs_csv'],
};
sub csv_select_fields {
    my %args = @_;
    csvutil(%args, action=>'select-fields');
}

$SPEC{csv_dump} = {
    v => 1.1,
    summary => 'Dump CSV as data structure (array of array/hash)',
    args => {
        %args_common,
        %arg_filename_0,
        %arg_hash,
    },
    description => '' . $common_desc,
};
sub csv_dump {
    my %args = @_;
    csvutil(%args, action=>'dump');
}

$SPEC{csv_csv} = {
    v => 1.1,
    summary => 'Convert CSV to CSV',
    description => <<'_' . $common_desc,

Why convert CSV to CSV? When you want to change separator/quote/escape
character, for one.

_
    args => {
        %args_common,
        %args_csv_output,
        %arg_filename_0,
        %arg_hash,
    },
};
sub csv_csv {
    my %args = @_;
    csvutil(%args, action=>'csv');
}

$SPEC{csv_setop} = {
    v => 1.1,
    summary => 'Set operation against several CSV files',
    description => <<'_' . $common_desc,

Example input:

    # file1.csv
    a,b,c
    1,2,3
    4,5,6
    7,8,9

    # file2.csv
    a,b,c
    1,2,3
    4,5,7
    7,8,9

Output of intersection (`--intersect file1.csv file2.csv`), which will return
common rows between the two files:

    a,b,c
    1,2,3
    7,8,9

Output of union (`--union file1.csv file2.csv`), which will return all rows with
duplicate removed:

    a,b,c
    1,2,3
    4,5,6
    4,5,7
    7,8,9

Output of difference (`--diff file1.csv file2.csv`), which will return all rows
in the first file but not in the second:

    a,b,c
    4,5,6

Output of symmetric difference (`--symdiff file1.csv file2.csv`), which will
return all rows in the first file not in the second, as well as rows in the
second not in the first:

    a,b,c
    4,5,6
    4,5,7

You can specify `--compare-fields` to only consider some fields only, for
example `--union --compare-fields a,b file1.csv file2.csv`:

    a,b,c
    1,2,3
    4,5,6
    7,8,9

Each field specified in `--compare-fields` can be specified using
`F1:OTHER1,F2:OTHER2,...` format to refer to different field names or indexes in
each file, for example if `file3.csv` is:

    # file3.csv
    Ei,Si,Bi
    1,3,2
    4,7,5
    7,9,8

Then `--union --compare-fields a:Ei,b:Bi file1.csv file3.csv` will result in:

    a,b,c
    1,2,3
    4,5,6
    7,8,9

Finally you can print out certain fields using `--result-fields`.

_
    args => {
        %args_common,
        %args_csv_output,
        %arg_filenames_0,
        op => {
            summary => 'Set operation to perform',
            schema => ['str*', in=>[qw/intersect union diff symdiff/]],
            req => 1,
            cmdline_aliases => {
                intersect   => {is_flag=>1, summary=>'Shortcut for --op=intersect', code=>sub{ $_[0]{op} = 'intersect' }},
                union       => {is_flag=>1, summary=>'Shortcut for --op=union'    , code=>sub{ $_[0]{op} = 'union'     }},
                diff        => {is_flag=>1, summary=>'Shortcut for --op=diff'     , code=>sub{ $_[0]{op} = 'diff'      }},
                symdiff     => {is_flag=>1, summary=>'Shortcut for --op=symdiff'  , code=>sub{ $_[0]{op} = 'symdiff'   }},
            },
        },
        ignore_case => {
            schema => 'bool*',
            cmdline_aliases => {i=>{}},
        },
        compare_fields => {
            schema => ['str*'],
        },
        result_fields => {
            schema => ['str*'],
        },
    },
    links => [
        {url=>'prog:setop'},
    ],
    tags => ['outputs_csv'],
};
sub csv_setop {
    require Tie::IxHash;

    my %args = @_;

    my $op = $args{op};
    my $ci = $args{ignore_case};
    my $num_files = @{ $args{filenames} };

    unless ($op ne 'cross' || $num_files > 1) {
        return [400, "Please specify at least 2 input files for cross"];
    }
    unless ($num_files >= 1) {
        return [400, "Please specify at least 1 input file"];
    }

    my @all_data_rows;   # elem=rows, one elem for each input file
    my @all_field_idxs;  # elem=field_idxs (hash, key=column name, val=index)
    my @all_field_names; # elem=[field1,field2,...] for 1st file, ...

    # read all csv
    for my $filename (@{ $args{filenames} }) {
        my $csv = _instantiate_parser(\%args);
        my $fh;
        if ($filename eq '-') {
            $fh = *STDIN;
        } else {
            open $fh, "<", $filename or
            return [500, "Can't open input filename '$filename': $!"];
        }
        binmode $fh, ":encoding(utf8)";
        my $i = 0;
        my @data_rows;
        my $field_idxs = {};
        while (my $row = $csv->getline($fh)) {
            $i++;
            if ($i == 1) {
                if ($args{header} // 1) {
                    my $fields = $row;
                    for my $field (@$fields) {
                        unless (exists $field_idxs->{$field}) {
                            $field_idxs->{$field} = keys(%$field_idxs);
                        }
                    }
                    push @all_field_names, $fields;
                    push @all_field_idxs, $field_idxs;
                    next;
                } else {
                    my $fields = [];
                    for (1..@$row) {
                        $field_idxs->{"field$_"} = $_-1;
                        push @$fields, "field$_";
                    }
                    push @all_field_names, $fields;
                    push @all_field_idxs, $field_idxs;
                }
            }
            push @data_rows, $row;
        }
        push @all_data_rows, \@data_rows;
    } # for each filename

    my @compare_fields; # elem = [fieldname-for-file1, fieldname-for-file2, ...]
    if (defined $args{compare_fields}) {
        my @ff = ref($args{compare_fields}) eq 'ARRAY' ?
            @{$args{compare_fields}} : split(/,/, $args{compare_fields});
        for my $field_idx (0..$#ff) {
            my @ff2 = split /:/, $ff[$field_idx];
            for (@ff2+1 .. $num_files) {
                push @ff2, $ff2[0];
            }
            $compare_fields[$field_idx] = \@ff2;
        }
    } else {
        for my $field_idx (0..$#{ $all_field_names[0] }) {
            $compare_fields[$field_idx] = [
                map { $all_field_names[0][$field_idx] } 0..$num_files-1];
        }
    }

    my @result_fields; # elem = fieldname, ...
    if (defined $args{result_fields}) {
        @result_fields = ref($args{result_fields}) eq 'ARRAY' ?
            @{$args{result_fields}} : split(/,/, $args{result_fields});
    } else {
        @result_fields = @{ $all_field_names[0] };
    }

    tie my(%res), 'Tie::IxHash';
    my $res = "";

    my $code_get_compare_key = sub {
        my ($file_idx, $row_idx) = @_;
        my $row   = $all_data_rows[$file_idx][$row_idx];
        my $key = join "|", map {
            my $field = $compare_fields[$_][$file_idx];
            my $field_idx = $all_field_idxs[$file_idx]{$field};
            my $val = defined $field_idx ? $row->[$field_idx] : "";
            $val = uc $val if $ci;
            $val;
        } 0..$#compare_fields;
        #say "D:compare_key($file_idx, $row_idx)=<$key>";
        $key;
    };

    my $csv = _instantiate_parser_default();
    my $code_format_result_row = sub {
        my ($file_idx, $row) = @_;
        my @res_row = map {
            my $field = $result_fields[$_];
            my $field_idx = $all_field_idxs[$file_idx]{$field};
            defined $field_idx ? $row->[$field_idx] : "";
        } 0..$#result_fields;
        $csv->combine(@res_row);
        $csv->string . "\n";
    };

    if ($op eq 'intersect') {
        for my $file_idx (0..$num_files-1) {
            if ($file_idx == 0) {
                for my $row_idx (0..$#{ $all_data_rows[$file_idx] }) {
                    my $key = $code_get_compare_key->($file_idx, $row_idx);
                    $res{$key} //= [1, $row_idx]; # [num_of_occurrence, row_idx]
                }
            } else {
                for my $row_idx (0..$#{ $all_data_rows[$file_idx] }) {
                    my $key = $code_get_compare_key->($file_idx, $row_idx);
                    if ($res{$key} && $res{$key}[0] == $file_idx) {
                        $res{$key}[0]++;
                    }
                }
            }

            # build result
            if ($file_idx == $num_files-1) {
                #use DD; dd \%res;
                $csv->combine(@result_fields);
                $res .= $csv->string . "\n";
                for my $key (keys %res) {
                    $res .= $code_format_result_row->(
                        0, $all_data_rows[0][$res{$key}[1]])
                        if $res{$key}[0] == $num_files;
                }
            }
        } # for file_idx

    } elsif ($op eq 'union') {
        $csv->combine(@result_fields);
        $res .= $csv->string . "\n";

        for my $file_idx (0..$num_files-1) {
            for my $row_idx (0..$#{ $all_data_rows[$file_idx] }) {
                my $key = $code_get_compare_key->($file_idx, $row_idx);
                next if $res{$key}++;
                my $row = $all_data_rows[$file_idx][$row_idx];
                $res .= $code_format_result_row->($file_idx, $row);
            }
        } # for file_idx

    } elsif ($op eq 'diff') {
        for my $file_idx (0..$num_files-1) {
            if ($file_idx == 0) {
                for my $row_idx (0..$#{ $all_data_rows[$file_idx] }) {
                    my $key = $code_get_compare_key->($file_idx, $row_idx);
                    $res{$key} //= [$file_idx, $row_idx];
                }
            } else {
                for my $row_idx (0..$#{ $all_data_rows[$file_idx] }) {
                    my $key = $code_get_compare_key->($file_idx, $row_idx);
                    delete $res{$key};
                }
            }

            # build result
            if ($file_idx == $num_files-1) {
                $csv->combine(@result_fields);
                $res .= $csv->string . "\n";
                for my $key (keys %res) {
                    my ($file_idx, $row_idx) = @{ $res{$key} };
                    $res .= $code_format_result_row->(
                        0, $all_data_rows[$file_idx][$row_idx]);
                }
            }
        } # for file_idx

    } elsif ($op eq 'symdiff') {
        for my $file_idx (0..$num_files-1) {
            if ($file_idx == 0) {
                for my $row_idx (0..$#{ $all_data_rows[$file_idx] }) {
                    my $key = $code_get_compare_key->($file_idx, $row_idx);
                    $res{$key} //= [1, $file_idx, $row_idx];  # [num_of_occurrence, file_idx, row_idx]
                }
            } else {
                for my $row_idx (0..$#{ $all_data_rows[$file_idx] }) {
                    my $key = $code_get_compare_key->($file_idx, $row_idx);
                    if (!$res{$key}) {
                        $res{$key} = [1, $file_idx, $row_idx];
                    } else {
                        $res{$key}[0]++;
                    }
                }
            }

            # build result
            if ($file_idx == $num_files-1) {
                $csv->combine(@result_fields);
                $res .= $csv->string . "\n";
                for my $key (keys %res) {
                    my ($num_occur, $file_idx, $row_idx) = @{ $res{$key} };
                    $res .= $code_format_result_row->(
                        0, $all_data_rows[$file_idx][$row_idx])
                        if $num_occur == 1;
                }
            }
        } # for file_idx

    } else {
        return [400, "Unknown/unimplemented op '$op'"];
    }

    #use DD; dd +{
    #    compare_fields => \@compare_fields,
    #    result_fields => \@result_fields,
    #    all_field_idxs=>\@all_field_idxs,
    #    all_data_rows=>\@all_data_rows,
    #};

    [200, "OK", $res, {"cmdline.skip_format"=>1}];
}

$SPEC{csv_lookup_fields} = {
    v => 1.1,
    summary => 'Fill fields of a CSV file from another',
    description => <<'_' . $common_desc,

Example input:

    # report.csv
    client_id,followup_staff,followup_note,client_email,client_phone
    101,Jerry,not renewing,
    299,Jerry,still thinking over,
    734,Elaine,renewing,

    # clients.csv
    id,name,email,phone
    101,Andy,andy@example.com,555-2983
    102,Bob,bob@acme.example.com,555-2523
    299,Cindy,cindy@example.com,555-7892
    400,Derek,derek@example.com,555-9018
    701,Edward,edward@example.com,555-5833
    734,Felipe,felipe@example.com,555-9067

To fill up the `client_email` and `client_phone` fields of `report.csv` from
`clients.csv`, we can use: `--lookup-fields client_id:id --fill-fields
client_email:email,client_phone:phone`. The result will be:

    client_id,followup_staff,followup_note,client_email,client_phone
    101,Jerry,not renewing,andy@example.com,555-2983
    299,Jerry,still thinking over,cindy@example.com,555-7892
    734,Elaine,renewing,felipe@example.com,555-9067

_
    args => {
        %args_common,
        %args_csv_output,
        target => {
            summary => 'CSV file to fill fields of',
            schema => 'filename*',
            req => 1,
            pos => 0,
        },
        source => {
            summary => 'CSV file to lookup values from',
            schema => 'filename*',
            req => 1,
            pos => 1,
        },
        ignore_case => {
            schema => 'bool*',
            cmdline_aliases => {i=>{}},
        },
        fill_fields => {
            schema => ['str*'],
            req => 1,
        },
        lookup_fields => {
            schema => ['str*'],
            req => 1,
        },
        count => {
            summary => 'Do not output rows, just report the number of rows filled',
            schema => 'bool*',
            cmdline_aliases => {c=>{}},
        },
    },
    tags => ['outputs_csv'],
};
sub csv_lookup_fields {
    my %args = @_;

    my $op = $args{op};
    my $ci = $args{ignore_case};

    my @lookup_fields; # elem = [fieldname-in-target, fieldname-in-source]
    {
        my @ff = ref($args{lookup_fields}) eq 'ARRAY' ?
            @{$args{lookup_fields}} : split(/,/, $args{lookup_fields});
        for my $field_idx (0..$#ff) {
            my @ff2 = split /:/, $ff[$field_idx], 2;
            if (@ff2 < 2) {
                $ff2[1] = $ff2[0];
            }
            $lookup_fields[$field_idx] = \@ff2;
        }
    }

    my %fill_fields; # key=fieldname-in-target, val=fieldname-in-source
    {
        my @ff = ref($args{fill_fields}) eq 'ARRAY' ?
            @{$args{fill_fields}} : split(/,/, $args{fill_fields});
        for my $field_idx (0..$#ff) {
            my @ff2 = split /:/, $ff[$field_idx], 2;
            if (@ff2 < 2) {
                $ff2[1] = $ff2[0];
            }
            $fill_fields{ $ff2[0] } = $ff2[1];
        }
    }

    # read source csv
    my @source_data_rows;
    my %source_field_idxs;
    my @source_field_names;
    {
        my $csv = _instantiate_parser(\%args);
        my $fh;
        if ($args{source} eq '-') {
            $fh = *STDIN;
        } else {
            open $fh, "<", $args{source} or
            return [500, "Can't open source '$args{source}': $!"];
        }
        binmode $fh, ":encoding(utf8)";

        my $i = 0;
        while (my $row = $csv->getline($fh)) {
            $i++;
            if ($i == 1) {
                if ($args{header} // 1) {
                    @source_field_names = @$row;
                    for my $field (@source_field_names) {
                        unless (exists $source_field_idxs{$field}) {
                            $source_field_idxs{$field} = keys(%source_field_idxs);
                        }
                    }
                    next;
                } else {
                    for (1..@$row) {
                        $source_field_idxs{"field$_"} = $_-1;
                        push @source_field_names, "field$_";
                    }
                }
            }
            push @source_data_rows, $row;
        }
    }

    # build lookup table
    my %lookup_table; # key = joined lookup fields, val = source row idx
    for my $row_idx (0..$#{source_data_rows}) {
        my $row = $source_data_rows[$row_idx];
        my $key = join "|", map {
            my $field = $lookup_fields[$_][1];
            my $field_idx = $source_field_idxs{$field};
            my $val = defined $field_idx ? $row->[$field_idx] : "";
            $val = lc $val if $ci;
            $val;
        } 0..$#lookup_fields;
        $lookup_table{$key} //= $row_idx;
    }
    #use DD; dd { lookup_fields=>\@lookup_fields, fill_fields=>\%fill_fields, lookup_table=>\%lookup_table };

    # fill target csv
    my $res = "";
    my @target_field_names;
    my %target_field_idxs;
    my $num_filled = 0;
    {
        my $csv_out = _instantiate_parser_default();
        my $csv = _instantiate_parser(\%args);
        my $fh;
        if ($args{target} eq '-') {
            $fh = *STDIN;
        } else {
            open $fh, "<", $args{target} or
                return [500, "Can't open target '$args{target}': $!"];
        }
        binmode $fh, ":encoding(utf8)";

        my $i = 0;
        while (my $row = $csv->getline($fh)) {
            $i++;
            if ($i == 1) {
                if ($args{header} // 1) {
                    $csv_out->combine(@$row);
                    $res .= $csv_out->string . "\n";
                    @target_field_names = @$row;
                    for my $field (@target_field_names) {
                        unless (exists $target_field_idxs{$field}) {
                            $target_field_idxs{$field} = keys(%target_field_idxs);
                        }
                    }
                    next;
                } else {
                    for (1..@$row) {
                        $target_field_idxs{"field$_"} = $_-1;
                        push @target_field_names, "field$_";
                    }
                }
            }

            my $key = join "|", map {
                my $field = $lookup_fields[$_][0];
                my $field_idx = $target_field_idxs{$field};
                my $val = defined $field_idx ? $row->[$field_idx] : "";
                $val = lc $val if $ci;
                $val;
            } 0..$#lookup_fields;

            #say "D:looking up '$key' ...";
            if (defined(my $row_idx = $lookup_table{$key})) {
                #say "  D:found";
                my $row_filled;
                my $source_row = $source_data_rows[$row_idx];
                for my $field (keys %fill_fields) {
                    my $target_field_idx = $target_field_idxs{$field};
                    next unless defined $target_field_idx;
                    my $source_field_idx = $source_field_idxs{ $fill_fields{$field} };
                    next unless defined $source_field_idx;
                    $row->[$target_field_idx] =
                        $source_row->[$source_field_idx];
                    $row_filled++;
                }
                $num_filled++ if $row_filled;
            }
            $csv_out->combine(@$row);
            unless ($args{count}) {
                $res .= $csv_out->string . "\n";
            }
        }
    }

    if ($args{count}) {
        [200, "OK", $num_filled];
    } else {
        [200, "OK", $res, {"cmdline.skip_format"=>1}];
    }
}

1;
# ABSTRACT: CLI utilities related to CSV

=for Pod::Coverage ^(csvutil)$

=head1 DESCRIPTION

This distribution contains the following CLI utilities:

# INSERT_EXECS_LIST


=head1 FAQ

=head2 My CSV does not have a header?

Use the C<--no-header> option. Fields will be named C<field1>, C<field2>, and so
on.

=head2 My data is TSV, not CSV?

Use the C<--tsv> option.

=head2 I have a big CSV and the utilities are too slow or eat too much RAM!

These utilities are not (yet) optimized, patches welcome. If your CSV is very
big, perhaps a C-based solution is what you need.


=head1 SEE ALSO

=head2 Similar CLI bundles for other format

L<App::TSVUtils>, L<App::LTSVUtils>, L<App::SerializeUtils>.

=head2 Other CSV-related utilities

L<xls2csv> and L<xlsx2csv> from L<Spreadsheet::Read>

L<import-csv-to-sqlite> from L<App::SQLiteUtils>

Query CSV with SQL using L<fsql> from L<App::fsql>

L<csvgrep> from L<csvgrep>

=cut
