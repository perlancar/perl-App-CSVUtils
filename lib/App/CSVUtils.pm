package App::CSVUtils;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

our %SPEC;

sub _compile {
    my $str = shift;
    return $str if ref $str eq 'CODE';
    defined($str) && length($str) or die "Please specify code (-e)\n";
    $str = "package main; no strict; no warnings; sub { $str }";
    my $code = eval $str;
    die "Can't compile code (-e) '$str': $@\n" if $@;
    $code;
}

sub _get_field_idx {
    my ($field, $field_idxs) = @_;
    defined($field) && length($field) or die "Please specify field (-F)\n";
    my $idx = $field_idxs->{$field};
    die "Unknown field '$field'\n" unless defined $idx;
    $idx;
}

sub _get_csv_row {
    my ($csv, $row, $i, $has_header) = @_;
    return "" if $i == 1 && !$has_header;
    my $status = $csv->combine(@$row)
        or die "Error in line $i: ".$csv->error_input."\n";
    $csv->string . "\n";
}

sub _complete_field_or_field_list {
    # return list of known fields of a CSV

    my $which = shift;

    my %args = @_;
    my $word = $args{word} // '';
    my $cmdline = $args{cmdline};
    my $r = $args{r};

    # we are not called from cmdline, bail
    return undef unless $cmdline;

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
    return undef unless defined $args && $args->{filename};

    # can the file be opened?
    require Text::CSV_XS;
    my $csv = Text::CSV_XS->new({binary => 1});
    open my($fh), "<:encoding(utf8)", $args->{filename} or
        return [];

    # can the header row be read?
    my $row = $csv->getline($fh) or return [];

    require Complete::Util;
    if ($which eq 'field') {
        return Complete::Util::complete_array_elem(
            word => $word,
            array => $row,
        );
    } else {
        # field_list
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

my %args_common = (
    header => {
        summary => 'Whether CSV has a header row',
        schema => 'bool*',
        default => 1,
        description => <<'_',

When you declare that CSV does not have header row (`--no-header`), the fields
will be named `field1`, `field2`, and so on.

_
    },
);

my %arg_filename_1 = (
    filename => {
        summary => 'Input CSV file',
        schema => 'filename*',
        req => 1,
        pos => 1,
        cmdline_aliases => {f=>{}},
    },
);

my %arg_filename_0 = (
    filename => {
        summary => 'Input CSV file',
        schema => 'filename*',
        req => 1,
        pos => 0,
        cmdline_aliases => {f=>{}},
    },
);

my %arg_filenames_0 = (
    filenames => {
        'x.name.is_plural' => 1,
        summary => 'Input CSV files',
        schema => ['array*', of=>'filename*'],
        req => 1,
        pos => 0,
        greedy => 1,
        cmdline_aliases => {f=>{}},
    },
);

my %arg_field_1 = (
    field => {
        summary => 'Field name',
        schema => 'str*',
        cmdline_aliases => { F=>{} },
        req => 1,
        pos => 1,
        completion => \&_complete_field,
    },
);

my %arg_field_1_nocomp = (
    field => {
        summary => 'Field name',
        schema => 'str*',
        cmdline_aliases => { F=>{} },
        req => 1,
        pos => 1,
    },
);

my %arg_fields_1 = (
    fields => {
        'x.name.is_plural' => 1,
        summary => 'Field names',
        schema => ['array*', of=>'str*'],
        cmdline_aliases => { F=>{} },
        req => 1,
        pos => 1,
        greedy => 1,
        element_completion => \&_complete_field,
    },
);

my %arg_fields_or_field_pat = (
    fields => {
        'x.name.is_plural' => 1,
        summary => 'Field names',
        schema => ['array*', of=>'str*'],
        cmdline_aliases => { F=>{} },
        pos => 1,
        greedy => 1,
        element_completion => \&_complete_field,
    },
    field_pat => {
        summary => 'Field regex pattern to select',
        schema => 're*',
    },
);

my %arg_eval_2 = (
    eval => {
        summary => 'Perl code to do munging',
        schema => 'str*',
        cmdline_aliases => { e=>{} },
        req => 1,
        pos => 2,
    },
);

my %args_sort = (
    sort_reverse => {
        schema => ['bool', is=>1],
    },
    sort_ci => {
        schema => ['bool', is=>1],
    },
    sort_example => {
        schema => ['array*', of=>'str*',
                   'x.perl.coerce_rules' => ['str_comma_sep']],
    },
);

my %args_sort_short = (
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

my %arg_with_data_rows = (
    with_data_rows => {
        summary => 'Whether to also output data rows',
        schema => 'bool',
    },
);

my %arg_eval = (
    eval => {
        summary => 'Perl code',
        schema => 'str*',
        cmdline_aliases => { e=>{} },
        req => 1,
    },
);

my %arg_hash = (
    hash => {
        summary => 'Provide row in $_ as hashref instead of arrayref',
        schema => ['bool*', is=>1],
        cmdline_aliases => {H=>{}},
    },
);

$SPEC{csvutil} = {
    v => 1.1,
    summary => 'Perform action on a CSV file',
    'x.no_index' => 1,
    args => {
        %args_common,
        action => {
            schema => ['str*', in=>[
                'list-field-names',
                'munge-field',
                'delete-field',
                'add-field',
                'sort-fields',
                'sum',
                'avg',
                'select-row',
                'grep',
                'map',
                'convert-to-hash',
                'select-fields',
            ]],
            req => 1,
            pos => 0,
            cmdline_aliases => {a=>{}},
        },
        %arg_filename_1,
        eval => {
            summary => 'Perl code to do munging',
            schema => ['any*', of=>['str*', 'code*']],
            cmdline_aliases => { e=>{} },
        },
        field => {
            summary => 'Field name',
            schema => 'str*',
            cmdline_aliases => { F=>{} },
        },
    },
    args_rels => {
    },
};
sub csvutil {
    require Text::CSV_XS;

    my %args = @_;
    my $action = $args{action};
    my $has_header = $args{header} // 1;
    my $add_newline = $args{add_newline} // 1;

    my $csv = Text::CSV_XS->new({binary => 1});
    open my($fh), "<:encoding(utf8)", $args{filename} or
        return [500, "Can't open input filename '$args{filename}': $!"];

    my $res = "";
    my $i = 0;
    my $fields;
    my %field_idxs;

    my $code;
    my $field_idx;
    my $field_idxs;
    my $sorted_fields;
    my @summary_row;
    my $selected_row;
    my $row_spec_sub;

    my $row0;
    my $code_getline = sub {
        if ($i == 0 && !$has_header) {
            $row0 = $csv->getline($fh);
            return unless $row0;
            return [map { "field$_" } 1..@$row0];
        } elsif ($i == 1 && !$has_header) {
            return $row0;
        }
        $csv->getline($fh);
    };

    while (my $row = $code_getline->()) {
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
                $row_spec_sub = eval 'sub { my $i = shift; '.join(" || ", @codestr).' }';
                return [400, "BUG: Invalid row_spec code: $@"] if $@;
            }
            if ($action eq 'grep') {
            } elsif ($action eq 'map') {
            }
        } # if i==1 (header row)

        if ($action eq 'list-field-names') {
            return [200, "OK",
                    [map { {name=>$_, index=>$field_idxs{$_}+1} }
                         sort keys %field_idxs],
                    {'table.fields'=>['name','index']}];
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
                    eval { $code->($_) };
                    die "Error while munging row ".
                        "#$i field '$args{field}' value '$_': $@\n" if $@;
                    $row->[$field_idx] = $_;
                }
            }
            $res .= _get_csv_row($csv, $row, $i, $has_header);
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
                    eval { $_ = $code->() };
                    die "Error while adding field '$args{field}' for row #$i: $@\n"
                        if $@;
                    splice @$row, $field_idx, 0, $_;
                }
            }
            $res .= _get_csv_row($csv, $row, $i, $has_header);
        } elsif ($action eq 'delete-field') {
            if (!defined($field_idxs)) {
                $field_idxs = [];
                for my $f (@{ $args{_fields} }) {
                    push @$field_idxs, _get_field_idx($f, \%field_idxs);
                }
                $field_idxs = [sort {$b<=>$a} @$field_idxs];
                for (@$field_idxs) {
                    splice @$row, $_, 1;
                    unless (@$row) {
                        return [412, "Can't delete field(s) because CSV will have zero fields"];
                    }
                }
            } else {
                for (@$field_idxs) {
                    splice @$row, $_, 1;
                }
            }
            $res .= _get_csv_row($csv, $row, $i, $has_header);
        } elsif ($action eq 'select-fields') {
            if (!defined($field_idxs)) {
                $field_idxs = [];
                my %seen;
                if ($args{_fields}) {
                    for my $f (@{ $args{_fields} }) {
                        return [400, "Duplicate field '$f'"] if $seen{$f}++;
                        push @$field_idxs, _get_field_idx($f, \%field_idxs);
                    }
                } else {
                    for my $f (@$fields) {
                        next unless $f =~ $args{_field_pat};
                        push @$field_idxs, $field_idxs{$f};
                    }
                }
            }
            $row = [map { $row->[$_] } @$field_idxs];
            $res .= _get_csv_row($csv, $row, $i, $has_header);
        } elsif ($action eq 'sort-fields') {
            unless ($i == 1) {
                my @new_row;
                for (@$sorted_fields) {
                    push @new_row, $row->[$field_idxs{$_}];
                }
                $row = \@new_row;
            }
            $res .= _get_csv_row($csv, $row, $i, $has_header);
        } elsif ($action eq 'sum') {
            if ($i == 1) {
                $res .= _get_csv_row($csv, $row, $i, $has_header);
            } else {
                require Scalar::Util;
                for (0..$#{$row}) {
                    next unless Scalar::Util::looks_like_number($row->[$_]);
                    $summary_row[$_] += $row->[$_];
                }
                $res .= _get_csv_row($csv, $row, $i, $has_header)
                    if $args{_with_data_rows};
            }
        } elsif ($action eq 'avg') {
            if ($i == 1) {
                $res .= _get_csv_row($csv, $row, $i, $has_header);
            } else {
                require Scalar::Util;
                for (0..$#{$row}) {
                    next unless Scalar::Util::looks_like_number($row->[$_]);
                    $summary_row[$_] += $row->[$_];
                }
                $res .= _get_csv_row($csv, $row, $i, $has_header)
                    if $args{_with_data_rows};
            }
        } elsif ($action eq 'select-row') {
            if ($i == 1 || $row_spec_sub->($i)) {
                $res .= _get_csv_row($csv, $row, $i, $has_header);
            }
        } elsif ($action eq 'grep') {
            unless ($code) {
                $code = _compile($args{eval});
            }
            if ($i == 1 || do {
                my $rowhash;
                if ($args{hash}) {
                    $rowhash = {};
                    for (0..$#{$fields}) {
                        $rowhash->{ $fields->[$_] } = $row->[$_];
                    }
                }
                local $_ = $args{hash} ? $rowhash : $row;
                local $main::row = $row;
                local $main::rownum = $i;
                $code->($row);
            }) {
                $res .= _get_csv_row($csv, $row, $i, $has_header);
            }
        } elsif ($action eq 'map') {
            unless ($code) {
                $code = _compile($args{eval});
            }
            if ($i > 1) {
                my $rowres = do {
                    my $rowhash;
                    if ($args{hash}) {
                        $rowhash = {};
                        for (0..$#{$fields}) {
                            $rowhash->{ $fields->[$_] } = $row->[$_];
                        }
                    }
                    local $_ = $args{hash} ? $rowhash : $row;
                    local $main::row = $row;
                    local $main::rownum = $i;
                    $code->($row);
                } // '';
                unless (!$add_newline || $rowres =~ /\R\z/) {
                    $rowres .= "\n";
                }
                $res .= $rowres;
            }
        } elsif ($action eq 'convert-to-hash') {
            if ($i == $args{_row_number}) {
                $selected_row = $row;
            }
        } else {
            return [400, "Unknown action '$action'"];
        }
    } # while getline()

    if ($action eq 'convert-to-hash') {
        $selected_row //= [];
        my $hash = {};
        for (0..$#{$fields}) {
            $hash->{ $fields->[$_] } = $selected_row->[$_];
        }
        return [200, "OK", $hash];
    }

    if ($action eq 'sum') {
        $res .= _get_csv_row($csv, \@summary_row,
                             $args{_with_data_rows} ? $i+1 : 2,
                             $has_header);
    } elsif ($action eq 'avg') {
        if ($i > 2) {
            for (@summary_row) { $_ /= ($i-1) }
        }
        $res .= _get_csv_row($csv, \@summary_row,
                             $args{_with_data_rows} ? $i+1 : 2,
                             $has_header);
    }
    [200, "OK", $res, {"cmdline.skip_format"=>1}];
}

$SPEC{csv_add_field} = {
    v => 1.1,
    summary => 'Add a field to CSV file',
    description => <<'_',

Your Perl code (-e) will be called for each row (excluding the header row) and
should return the value for the new field. `$main::row` is available and
contains the current row, while `$main::rownum` contains the row number (2 means
the first data row).

Field by default will be added as the last field, unless you specify one of
`--after` (to put after a certain field), `--before` (to put before a certain
field), or `--at` (to put at specific position, 1 means as the first field).

_
    args => {
        %args_common,
        %arg_filename_0,
        %arg_field_1_nocomp,
        %arg_eval_2,
        after => {
            summary => 'Put the new field after specified field',
            schema => 'str*',
        },
        before => {
            summary => 'Put the new field before specified field',
            schema => 'str*',
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
};
sub csv_list_field_names {
    my %args = @_;
    csvutil(%args, action=>'list-field-names');
}

$SPEC{csv_delete_field} = {
    v => 1.1,
    summary => 'Delete one or more fields from CSV file',
    args => {
        %args_common,
        %arg_filename_0,
        %arg_fields_1,
    },
};
sub csv_delete_field {
    my %args = @_;
    csvutil(%args, action=>'delete-field', _fields => $args{fields});
}

$SPEC{csv_munge_field} = {
    v => 1.1,
    summary => 'Munge a field in every row of CSV file',
    description => <<'_',

Perl code (-e) will be called for each row (excluding the header row) and `$_`
will contain the value of the field, and the Perl code is expected to modify it.
`$main::row` will contain the current row array and `$main::rownum` contains the
row number (2 means the first data row).

_
    args => {
        %args_common,
        %arg_filename_0,
        %arg_field_1,
        %arg_eval_2,
    },
};
sub csv_munge_field {
    my %args = @_;
    csvutil(%args, action=>'munge-field');
}

$SPEC{csv_replace_newline} = {
    v => 1.1,
    summary => 'Replace newlines in CSV values',
    description => <<'_',

Some CSV parsers or applications cannot handle multiline CSV values. This
utility can be used to convert the newline to something else. There are a few
choices: replace newline with space (`--with-space`, the default), remove
newline (`--with-nothing`), replace with encoded representation
(`--with-backslash-n`), or with characters of your choice (`--with 'blah'`).

_
    args => {
        %args_common,
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
};
sub csv_replace_newline {
    require Text::CSV_XS;

    my %args = @_;
    my $with = $args{with};

    my $csv = Text::CSV_XS->new({binary => 1});
    open my($fh), "<:encoding(utf8)", $args{filename} or
        return [500, "Can't open input filename '$args{filename}': $!"];

    my $res = "";
    my $i = 0;
    while (my $row = $csv->getline($fh)) {
        $i++;
        for my $col (@$row) {
            $col =~ s/[\015\012]+/$with/g;
        }
        my $status = $csv->combine(@$row)
            or die "Error in line $i: ".$csv->error_input;
        $res .= $csv->string . "\n";
    }

    [200, "OK", $res, {"cmdline.skip_format"=>1}];
}

$SPEC{csv_sort_fields} = {
    v => 1.1,
    summary => 'Sort CSV fields',
    args => {
        %args_common,
        %arg_filename_0,
        %args_sort_short,
    },
};
sub csv_sort_fields {
    my %args = @_;

    my %csvutil_args = (
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
        %arg_filename_0,
        %arg_with_data_rows,
    },
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
        %arg_filename_0,
        %arg_with_data_rows,
    },
};
sub csv_avg {
    my %args = @_;

    csvutil(%args, action=>'avg', _with_data_rows=>$args{with_data_rows});
}

$SPEC{csv_select_row} = {
    v => 1.1,
    summary => 'Only output specified row(s)',
    args => {
        %args_common,
        %arg_filename_0,
        row_spec => {
            schema => 'str*',
            summary => 'Row number (e.g. 2 for first data row), '.
                'range (2-7), or comma-separated list of such (2-7,10,20-23)',
            req => 1,
            pos => 1,
        },
    },
};
sub csv_select_row {
    my %args = @_;

    csvutil(%args, action=>'select-row');
}

$SPEC{csv_grep} = {
    v => 1.1,
    summary => 'Only output row(s) where Perl expression returns true',
    description => <<'_',

This is like Perl's `grep` performed over rows of CSV. In `$_`, your Perl code
will find the CSV row as an arrayref (or, if you specify `-H`, as a hashref).
`$main::row` is also set to the row (always as arrayref), while `$main::rownum`
contains the row number (2 means the first data row). Your code is then free to
return true or false based on some criteria. Only rows where Perl expression
returns true will be included in the result.

_
    args => {
        %args_common,
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
};
sub csv_grep {
    my %args = @_;

    csvutil(%args, action=>'grep');
}

$SPEC{csv_map} = {
    v => 1.1,
    summary => 'Return result of Perl code for every row',
    description => <<'_',

This is like Perl's `map` performed over rows of CSV. In `$_`, your Perl code
will find the CSV row as an arrayref (or, if you specify `-H`, as a hashref).
`$main::row` is also set to the row (always as arrayref), while `$main::rownum`
contains the row number (2 means the first data row). Your code is then free to
return a string based on some operation against these data. This utility will
then print out the resulting string.

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
};
sub csv_convert_to_hash {
    my %args = @_;

    csvutil(%args, action=>'convert-to-hash',
            _row_number=>$args{row_number} // 2);
}

$SPEC{csv_concat} = {
    v => 1.1,
    summary => 'Concatenate several CSV files together, '.
        'collecting all the fields',
    description => <<'_',

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
        %arg_filenames_0,
    },
};
sub csv_concat {
    require Text::CSV_XS;

    my %args = @_;

    my %res_field_idxs;
    my @rows;

    for my $filename (@{ $args{filenames} }) {
        my $csv = Text::CSV_XS->new({binary => 1});
        open my($fh), "<:encoding(utf8)", $filename or
            return [500, "Can't open input filename '$filename': $!"];
        my $i = 0;
        my $fields;
        while (my $row = $csv->getline($fh)) {
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
    my $csv = Text::CSV_XS->new({binary => 1});

    # generate header
    my $status = $csv->combine(
        sort { $res_field_idxs{$a} <=> $res_field_idxs{$b} }
            keys %res_field_idxs)
        or die "Error in generating result header row: ".$csv->error_input;
    $res .= $csv->string . "\n";
    for my $i (0..$#rows) {
        my $row = $rows[$i];
        $row->[$num_fields-1] = undef if @$row < $num_fields;
        my $status = $csv->combine(@$row)
            or die "Error in generating data row #".($i+1).": ".
            $csv->error_input;
        $res .= $csv->string . "\n";
    }
    [200, "OK", $res, {"cmdline.skip_format"=>1}];
}

$SPEC{csv_select_fields} = {
    v => 1.1,
    summary => 'Only output selected field(s)',
    args => {
        %args_common,
        %arg_filename_0,
        %arg_fields_or_field_pat,
    },
    args_rels => {
        req_one => ['fields', 'field_pat'],
    },
};
sub csv_select_fields {
    my %args = @_;
    csvutil(%args, action=>'select-fields',
            _fields => $args{fields}, _field_pat => $args{field_pat});
}

1;
# ABSTRACT: CLI utilities related to CSV

=for Pod::Coverage ^(csvutil)$

=head1 DESCRIPTION

This distribution contains the following CLI utilities:

# INSERT_EXECS_LIST


=head1 prepend:SEE ALSO

=cut
