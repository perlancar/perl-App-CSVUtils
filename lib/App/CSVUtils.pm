package App::CSVUtils;

use 5.010001;
use strict;
use warnings;
use Log::ger;

use Exporter qw(import);
use Hash::Subset qw(hash_subset);

# AUTHORITY
# DATE
# DIST
# VERSION

our @EXPORT_OK = qw(
                       gen_csv_util
                       compile_eval_code
               );

our %SPEC;

our $sch_req_str_or_code = ['any*', of=>['str*', 'code*']];

sub _open_file_read {
    my $filename = shift;

    my ($fh, $err);
    if ($filename eq '-') {
        $fh = *STDIN;
    } else {
        open $fh, "<", $filename or do {
            $err = [500, "Can't open input filename '$filename': $!"];
            goto RETURN;
        };
    }
    binmode $fh, ":encoding(utf8)";

  RETURN:
    ($fh, $err);
}

sub _open_file_write {
    my $filename = shift;

    my ($fh, $err);
    if ($filename eq '-') {
        $fh = *STDOUT;
    } else {
        open $fh, ">", $filename or do {
            $err = [500, "Can't open output filename '$filename': $!"];
            goto RETURN;
        };
    }
    binmode $fh, ":encoding(utf8)";

  RETURN:
    ($fh, $err);
}

sub _return_or_write_file {
    my ($res, $filename, $overwrite) = @_;
    return $res if !defined($filename);

    my $fh;
    if ($filename eq '-') {
        $fh = \*STDOUT;
    } else {
        if (-f $filename) {
            if ($overwrite) {
                log_info "Overwriting output file $filename";
            } else {
                return [412, "Refusing to ovewrite existing output file '$filename', please select another path or specify --overwrite"];
            }
        }
        open my $fh, ">", $filename or do {
            return [500, "Can't open output file '$filename': $!"];
        };
        binmode $fh, ":encoding(utf8)";
        print $fh $res->[2];
        close $fh or warn "Can't write to '$filename': $!";
        return [$res->[0], $res->[1]];
    }
}

sub compile_eval_code {
    return $_[0] if ref $_[0] eq 'CODE';
    my ($str, $label) = @_;
    defined($str) && length($str) or die [400, "Please specify code ($label)"];
    $str = "package main; no strict; no warnings; sub { $str }";
    log_trace "Compiling Perl code: $str";
    my $code = eval $str; ## no critic: BuiltinFunctions::ProhibitStringyEval
    die [400, "Can't compile code ($label) '$str': $@"] if $@;
    $code;
}

sub _get_field_idx {
    my ($field, $field_idxs) = @_;
    defined($field) && length($field) or die "Please specify at least a field\n";
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
    } elsif ($args->{"${prefix}tsv"}) {
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
    return {message=>"Please specify -f first"} unless defined $args && $args->{input_filename};

    # user wants to read CSV from stdin, bail
    return {message=>"Can't get field list when input is stdin"} if $args->{input_filename} eq '-';

    # can the file be opened?
    my $csv_parser = _instantiate_parser(\%args, 'input_');
    open my($fh), "<encoding(utf8)", $args->{input_filename} or do {
        #warn "csvutils: Cannot open file '$args->{input_filename}': $!\n";
        return [];
    };

    # can the header row be read?
    my $row = $csv_parser->getline($fh) or return [];

    if (defined $args->{input_header} && !$args->{input_header}) {
        $row = [map {"field$_"} 1 .. @$row];
    }

    if ($which =~ /sort/) {
        $row = [map {($_,"-$_","+$_","~$_")} @$row];
    }

    require Complete::Util;
    if ($which =~ /field_list/) {
        return Complete::Util::complete_comma_sep(
            word => $word,
            elems => $row,
            uniq => 1,
        );
    } else {
        return Complete::Util::complete_array_elem(
            word => $word,
            array => $row,
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

sub _complete_sort_field {
    _complete_field_or_field_list('sort_field', @_);
}

sub _array2hash {
    my ($row, $fields) = @_;
    my $rowhash = {};
    for my $i (0..$#{$fields}) {
        $rowhash->{ $fields->[$i] } = $row->[$i];
    }
    $rowhash;
}

sub _select_fields {
    my ($fields, $field_idxs, $args) = @_;

    my @selected_fields;

    if ($args->{pick_num}) {
        require List::Util;
        @selected_fields = List::Util::shuffle(@$fields);
        if ($args->{pick_num} < @selected_fields) {
            splice @selected_fields, 0, (@selected_fields-$args->{pick_num});
        }
    }

    if (defined $args->{include_field_pat}) {
        for my $field (@$fields) {
            if ($field =~ $args->{include_field_pat}) {
                push @selected_fields, $field;
            }
        }
    }
    if (defined $args->{exclude_field_pat}) {
        @selected_fields = grep { $_ !~ $args->{exclude_field_pat} }
            @selected_fields;
    }
    if (defined $args->{include_fields}) {
      FIELD:
        for my $field (@{ $args->{include_fields} }) {
            unless (defined $field_idxs->{$field}) {
                return [400, "Unknown field '$field'"] unless $args->{ignore_unknown_fields};
                next FIELD;
            }
            next if grep { $field eq $_ } @selected_fields;
            push @selected_fields, $field;
        }
    }
    if (defined $args->{exclude_fields}) {
      FIELD:
        for my $field (@{ $args->{exclude_fields} }) {
            unless (defined $field_idxs->{$field}) {
                return [400, "Unknown field '$field'"] unless $args->{ignore_unknown_fields};
                next FIELD;
            }
            @selected_fields = grep { $field ne $_ } @selected_fields;
        }
    }

    if ($args->{show_selected_fields}) {
        return [200, "OK", \@selected_fields];
    }

    #my %selected_field_idxs;
    #$selected_field_idxs{$_} = $fields_idx->{$_} for @selected_fields;

    my @selected_field_idxs_array;
    push @selected_field_idxs_array, $field_idxs->{$_} for @selected_fields;

    [100, "Continue", [\@selected_fields, \@selected_field_idxs_array]];
}

our %argspecs_csv_input = (
    input_header => {
        summary => 'Specify whether input CSV has a header row',
        'summary.alt.bool.not' => 'Specify that input CSV does not have a header row',
        schema => 'bool*',
        default => 1,
        description => <<'_',

By default, the first row of the input CSV will be assumed to contain field
names (and the second row contains the first data row). When you declare that
input CSV does not have header row (`--no-input-header`), the first row of the
CSV is assumed to contain the first data row. Fields will be named `field1`,
`field2`, and so on.

_
        cmdline_aliases => {
        },
        tags => ['category:input'],
    },
    input_tsv => {
        summary => "Inform that input file is in TSV (tab-separated) format instead of CSV",
        schema => 'true*',
        description => <<'_',

Overriden by `--input-sep-char`, `--input-quote-char`, `--input-escape-char`
options. If one of those options is specified, then `--input-tsv` will be
ignored.

_
        tags => ['category:input'],
    },
    input_sep_char => {
        summary => 'Specify field separator character in input CSV, will be passed to Text::CSV_XS',
        schema => ['str*', len=>1],
        description => <<'_',

Defaults to `,` (comma). Overrides `--input-tsv` option.

_
        tags => ['category:input'],
    },
    input_quote_char => {
        summary => 'Specify field quote character in input CSV, will be passed to Text::CSV_XS',
        schema => ['str*', len=>1],
        description => <<'_',

Defaults to `"` (double quote). Overrides `--input-tsv` option.

_
        tags => ['category:input'],
    },
    input_escape_char => {
        summary => 'Specify character to escape value in field in input CSV, will be passed to Text::CSV_XS',
        schema => ['str*', len=>1],
        description => <<'_',

Defaults to `\\` (backslash). Overrides `--input-tsv` option.

_
        tags => ['category:input'],
    },
);

our %argspecs_csv_output = (
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

This is like `--input-tsv` option but for output instead of input.

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

This is like `--input-sep-char` option but for output instead of input.

Defaults to `,` (comma). Overrides `--output-tsv` option.

_
        tags => ['category:output'],
    },
    output_quote_char => {
        summary => 'Specify field quote character in output CSV, will be passed to Text::CSV_XS',
        schema => ['str*', len=>1],
        description => <<'_',

This is like `--input-quote-char` option but for output instead of input.

Defaults to `"` (double quote). Overrides `--output-tsv` option.

_
        tags => ['category:output'],
    },
    output_escape_char => {
        summary => 'Specify character to escape value in field in output CSV, will be passed to Text::CSV_XS',
        schema => ['str*', len=>1],
        description => <<'_',

This is like `--input-escape-char` option but for output instead of input.

Defaults to `\\` (backslash). Overrides `--output-tsv` option.

_
        tags => ['category:output'],
    },
);

our %argspecopt_input_filename = (
    input_filename => {
        summary => 'Input CSV file',
        description => <<'_',

Use `-` to read from stdin.

Encoding of input file is assumed to be UTF-8.

_
        schema => 'filename*',
        default => '-',
        tags => ['category:input'],
    },
);

# old, for non-modularized utils
our %argspecopt_input_filename_0 = (
    input_filename => {
        summary => 'Input CSV file',
        description => <<'_',

Use `-` to read from stdin.

Encoding of input file is assumed to be UTF-8.

_
        schema => 'filename*',
        default => '-',
        pos => 0,
        tags => ['category:input'],
    },
);

# old, for non-modularized utils
our %argspecopt_input_filename_1 = (
    input_filename => {
        summary => 'Input CSV file',
        description => <<'_',

Use `-` to read from stdin.

Encoding of input file is assumed to be UTF-8.

_
        schema => 'filename*',
        default => '-',
        pos => 1,
        tags => ['category:input'],
    },
);

our %argspecopt_input_filenames = (
    input_filenames => {
        'x.name.is_plural' => 1,
        'x.name.singular' => 'input_filename',
        summary => 'Input CSV files',
        description => <<'_',

Use `-` to read from stdin.

Encoding of input file is assumed to be UTF-8.

_
        schema => ['array*', of=>'filename*'],
        default => ['-'],
        tags => ['category:input'],
    },
);

# old, for non-modularized utils
our %argspecopt_input_filenames_0plus = (
    input_filenames => {
        'x.name.is_plural' => 1,
        'x.name.singular' => 'input_filename',
        summary => 'Input CSV files',
        description => <<'_',

Use `-` to read from stdin.

Encoding of input file is assumed to be UTF-8.

_
        schema => ['array*', of=>'filename*'],
        default => ['-'],
        pos => 0,
        slurpy => 1,
        tags => ['category:input'],
    },
);

our %argspecopt_overwrite = (
    overwrite => {
        summary => 'Whether to override existing output file',
        schema => 'bool*',
        cmdline_aliases=>{O=>{}},
        tags => ['category:output'],
    },
);

our %argspecopt_output_filename = (
    output_filename => {
        summary => 'Output filename',
        description => <<'_',

Use `-` to output to stdout (the default if you don't specify this option).

Encoding of output file is assumed to be UTF-8.

_
        schema => 'filename*',
        cmdline_aliases=>{o=>{}},
        tags => ['category:output'],
    },
);

# old, for non-modularized utils
our %argspecopt_output_filename_1 = (
    output_filename => {
        summary => 'Output filename',
        description => <<'_',

Use `-` to output to stdout (the default if you don't specify this option).

Encoding of output file is assumed to be UTF-8.

_
        schema => 'filename*',
        pos => 1,
        cmdline_aliases=>{o=>{}},
        tags => ['category:output'],
    },
);

# old, for non-modularized utils
our %argspecopt_output_filename_2 = (
    output_filename => {
        summary => 'Output filename',
        description => <<'_',

Use `-` to output to stdout (the default if you don't specify this option).

Encoding of output file is assumed to be UTF-8.

_
        schema => 'filename*',
        pos => 2,
        cmdline_aliases=>{o=>{}},
        tags => ['category:output'],
    },
);

our %argspecopt_output_filenames = (
    output_filenames => {
        summary => 'Output filenames',
        description => <<'_',

Use `-` to output to stdout (the default if you don't specify this option).

Encoding of output file is assumed to be UTF-8.

_
        schema => ['array*', of=>'filename*'],
        cmdline_aliases=>{o=>{}},
        tags => ['category:output'],
    },
);

our %argspecopt_field = (
    field => {
        summary => 'Field name',
        schema => 'str*',
        cmdline_aliases => { F=>{} },
    },
);

our %argspec_field_1 = (
    field => {
        summary => 'Field name',
        schema => 'str*',
        cmdline_aliases => { F=>{} },
        req => 1,
        pos => 1,
        completion => \&_complete_field,
    },
);

# without completion, for adding new field
our %argspec_field_1_nocomp = (
    field => {
        summary => 'Field name',
        schema => 'str*',
        cmdline_aliases => { F=>{} },
        req => 1,
        pos => 1,
    },
);

# without completion, for adding new fields
our %argspec_fields_1plus_nocomp = (
    fields => {
        'x.name.is_plural' => 1,
        'x.name.singular' => 'field',
        summary => 'Field names',
        'summary.alt.plurality.singular' => 'Field name',
        schema => ['array*', of=>['str*', min_len=>1], min_len=>1],
        cmdline_aliases => { F=>{} },
        req => 1,
        pos => 1,
        slurpy => 1,
    },
);

our %argspec_fields = (
    fields => {
        'x.name.is_plural' => 1,
        'x.name.singular' => 'field',
        summary => 'Field names',
        schema => ['array*', of=>['str*', min_len=>1], min_len=>1],
        req => 1,
        cmdline_aliases => {F=>{}},
    },
);

our %argspecopt_fields = (
    fields => {
        'x.name.is_plural' => 1,
        'x.name.singular' => 'field',
        summary => 'Field names',
        schema => ['array*', of=>['str*', min_len=>1], min_len=>1],
        cmdline_aliases => {F=>{}},
    },
);
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
            include_all_fields => { summary => 'Shortcut for --field-pat=.*, effectively selecting all fields', is_flag=>1, code => sub { $_[0]{include_field_pat} = '.*' } },
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
            exclude_all_fields => { summary => 'Shortcut for --field-pat=.*, effectively selecting all fields', is_flag=>1, code => sub { $_[0]{exclude_field_pat} = '.*' } },
        },
        tags => ['category:field-selection'],
    },
    ignore_unknown_fields => {
        summary => 'When unknown fields are specified in --include-field (--field) or --exclude-field options, ignore them instead of throwing an error',
        schema => 'bool*',
    },
    show_selected_fields => {
        summary => 'Show selected fields and then immediately exit',
        schema => 'true*',
    },
);

our %argspecsopt_vcf = (
    name_vcf_field => {
        summary => 'Select field to use as VCF N (name) field',
        schema => 'str*',
    },
    cell_vcf_field => {
        summary => 'Select field to use as VCF CELL field',
        schema => 'str*',
    },
    email_vcf_field => {
        summary => 'Select field to use as VCF EMAIL field',
        schema => 'str*',
    },
);

our %argspec_eval = (
    eval => {
        summary => 'Perl code',
        schema => $sch_req_str_or_code,
        cmdline_aliases => { e=>{} },
        req => 1,
    },
);

our %argspecopt_eval = (
    eval => {
        summary => 'Perl code',
        schema => $sch_req_str_or_code,
        cmdline_aliases => { e=>{} },
    },
);

our %argspec_eval_1 = (
    eval => {
        summary => 'Perl code',
        schema => $sch_req_str_or_code,
        cmdline_aliases => { e=>{} },
        req => 1,
        pos => 1,
    },
);

our %argspec_eval_2 = (
    eval => {
        summary => 'Perl code',
        schema => $sch_req_str_or_code,
        cmdline_aliases => { e=>{} },
        req => 1,
        pos => 2,
    },
);

our %argspecopt_eval_2 = (
    eval => {
        summary => 'Perl code',
        schema => $sch_req_str_or_code,
        cmdline_aliases => { e=>{} },
        pos => 2,
    },
);

our %argspecopt_by_code = (
    by_code => {
        summary => 'Sort using Perl code',
        schema => $sch_req_str_or_code,
        description => <<'_',

`$a` and `$b` (or the first and second argument) will contain the two rows to be
compared. Which are arrayrefs; or if `--hash` (`-H`) is specified, hashrefs; or
if `--key` is specified, whatever the code in `--key` returns.

_
    },
);

our %argspecsopt_sortsub = (
    by_sortsub => {
        schema => 'str*',
        description => <<'_',

When sorting rows, usually combined with `--key` because most Sort::Sub routine
expects a string to be compared against.

When sorting fields, the Sort::Sub routine will get the field name as argument.

_
        summary => 'Sort using a Sort::Sub routine',
        'x.completion' => ['sortsub_spec'],
    },
    sortsub_args => {
        summary => 'Arguments to pass to Sort::Sub routine',
        schema => ['hash*', of=>'str*'],
    },
);

our %argspecopt_key = (
    key => {
        summary => 'Generate sort keys with this Perl code',
        description => <<'_',

If specified, then will compute sort keys using Perl code and sort using the
keys. Relevant when sorting using `--by-code` or `--by-sortsub`. If specified,
then instead of row when sorting rows, the code (or Sort::Sub routine) will
receive these sort keys to sort against.

Tthe code will receive the row (arrayref) as the argument.

_
        schema => $sch_req_str_or_code,
        cmdline_aliases => {k=>{}},
    },
);

# argspecs for csvutil
our %argspecsopt_sort = (
    sort_reverse => {
        schema => ['bool', is=>1],
    },
    sort_ci => {
        schema => ['bool', is=>1],
    },
    sort_by_sortsub => {
        schema => 'str*',
    },
    sort_sortsub_args => {
        schema => ['hash*'],
    },
    sort_by_code => {
        schema => $sch_req_str_or_code,
    },
    sort_key => {
        schema => $sch_req_str_or_code,
    },
    # for csv-sort-fields
    sort_examples => {
        schema => ['array*', of=>'str*'],
    },
);

# argspecs for csv-sort-rows
our %argspecs_sort_rows_short = (
    reverse => {
        schema => ['bool', is=>1],
        cmdline_aliases => {r=>{}},
    },
    ci => {
        schema => ['bool', is=>1],
        cmdline_aliases => {i=>{}},
    },
    by_fields => {
        summary => 'Sort by a list of field specifications',
        'summary.alt.plurality.singular' => 'Add a sort field specification',
        'x.name.is_plural' => 1,
        'x.name.singular' => 'by_field',
        description => <<'_',

Each field specification is a field name with an optional prefix. `FIELD`
(without prefix) means sort asciibetically ascending (smallest to largest),
`~FIELD` means sort asciibetically descending (largest to smallest), `+FIELD`
means sort numerically ascending, `-FIELD` means sort numerically descending.

_
        schema => ['array*', of=>'str*'],
        element_completion => \&_complete_sort_field,
    },
    %argspecopt_key,
    %argspecsopt_sortsub,
    %argspecopt_by_code,
);

# argspecs for csv-sort-fields
our %argspecs_sort_fields_short = (
    reverse => {
        schema => ['bool', is=>1],
        cmdline_aliases => {r=>{}},
    },
    ci => {
        schema => ['bool', is=>1],
        cmdline_aliases => {i=>{}},
    },
    by_examples => {
        summary => 'A list of field names to sort by example',
        'summary.alt.plurality.singular' => 'Add a field to sort by example',
        'x.name.is_plural' => 1,
        'x.name.singular' => 'by_example',
        schema => ['array*', of=>'str*'],
        element_completion => \&_complete_field,
    },
    %argspecopt_by_code,
    %argspecsopt_sortsub,
);

our %argspec_with_data_rows = (
    with_data_rows => {
        summary => 'Whether to also output data rows',
        schema => 'bool',
    },
);

our %argspec_hash = (
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
        %argspecs_csv_input,
        action => {
            schema => ['str*', in=>[
                'add-fields',
                'list-field-names',
                'info',
                'delete-fields',
                'munge-field',
                'munge-row',
                #'replace-newline', # not implemented in csvutil
                'sort-rows',
                'sort-fields',
                'select-rows',
                'split',
                'grep',
                'map',
                'each-row',
                'convert-to-hash',
                'convert-to-td',
                #'concat', # not implemented in csvutil
                'select-fields',
                #'setop', # not implemented in csvutil
                #'lookup-fields', # not implemented in csvutil
                'transpose',
                'freqtable',
                'get-cells',
                'fill-template',
                'convert-to-vcf',
                'pick-rows',
            ]],
            req => 1,
            pos => 0,
            cmdline_aliases => {a=>{}},
        },
        %argspecopt_input_filename_1,
        %argspecopt_output_filename_2,
        %argspecopt_overwrite,
        %argspecopt_eval,
        %argspecopt_field,
        %argspecsopt_field_selection,
        %argspecsopt_vcf,
        %argspecsopt_sort,
    },
    args_rels => {
    },
};
sub csvutil {
    my %args = @_;
    #use DD; dd \%args;

    my $action = $args{action};
    my $has_header = $args{input_header} // 1;
    my $outputs_header = $args{output_header} // $has_header;
    my $add_newline = $args{add_newline} // 1;

    my $csv_parser  = _instantiate_parser(\%args, 'input_');
    my $csv_emitter = _instantiate_emitter(\%args);

    my ($fh, $err) = _open_file_read($args{input_filename});
    return $err if $err;

    my $res = "";
    my $i = 0;
    my $header_row_count = 0;
    my $data_row_count = 0;

    my $fields = []; # field names, in order
    my %field_idxs; # key = field name, val = index (0-based)

    my $selected_fields;
    my $selected_field_idxs_array;
    my $selected_field_idxs_array_sorted;
    my $code;
    my $field_idx;
    my $sorted_fields;
    my $selected_row;
    my $row_spec_sub;
    my %freqtable; # key=value, val=frequency
    my @cells;

    # for action=split
    my ($split_fh, $split_filename, $split_lines);

    # for action convert-to-vcf
    my %fields_for;
    $fields_for{N}     = $args{name_vcf_field};
    $fields_for{CELL}  = $args{cell_vcf_field};
    $fields_for{EMAIL} = $args{email_vcf_field};

    my $row0;
    my $code_getline = sub {
        if ($i == 0 && !$has_header) {
            $row0 = $csv_parser->getline($fh);
            return unless $row0;
            return [map { "field$_" } 1..@$row0];
        } elsif ($i == 1 && !$has_header) {
            $data_row_count++ if $row0;
            return $row0;
        }
        my $res = $csv_parser->getline($fh);
        if ($res) {
            $header_row_count++ if $i==0;
            $data_row_count++ if $i;
        }
        $res;
    };

    my $rows = [];

    while (my $row = $code_getline->()) {
        #use DD; dd $row;<
        $i++;
        if ($i == 1) {
            # header row

            $fields = $row;
            for my $j (0..$#{$row}) {
                unless (length $row->[$j]) {
                    #return [412, "Empty field name in field #$j"];
                    next;
                }
                if (defined $field_idxs{ $row->[$j] }) {
                    return [412, "Duplicate field name '$row->[$j]'"];
                }
                $field_idxs{$row->[$j]} = $j;
            }

            if ($action eq 'sort-fields') {
                if (my $eg = $args{sort_examples}) {
                    require Sort::ByExample;
                    my $sorter = Sort::ByExample::sbe($eg);
                    $sorted_fields = [$sorter->(@$row)];
                } elsif ($args{sort_by_code} || $args{sort_by_sortsub}) {
                    my $code;
                    if ($args{sort_by_code}) {
                        $code = _compile($args{sort_by_code});
                    } elsif (defined $args{sort_by_sortsub}) {
                        require Sort::Sub;
                        $code = Sort::Sub::get_sorter(
                            $args{sort_by_sortsub}, $args{sort_sortsub_args});
                    }
                    $sorted_fields = [sort { local $main::a=$a; local $main::b=$b; $code->($main::a,$main::b) } @$fields];
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

            if ($action eq 'select-rows') {
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

            if ($action eq 'convert-to-vcf') {
                for my $field (@$fields) {
                    if ($field =~ /name/i && !defined($fields_for{N})) {
                        log_info "Will be using field '$field' for VCF field 'N' (name)";
                        $fields_for{N} = $field;
                    }
                    if ($field =~ /(e-?)?mail/i && !defined($fields_for{EMAIL})) {
                        log_info "Will be using field '$field' for VCF field 'EMAIL'";
                        $fields_for{EMAIL} = $field;
                    }
                    if ($field =~ /cell|hp|phone|wa|whatsapp/i && !defined($fields_for{CELL})) {
                        log_info "Will be using field '$field' for VCF field 'CELL' (cellular phone)";
                        $fields_for{CELL} = $field;
                    }
                }
                if (!defined($fields_for{N})) {
                    return [412, "Can't convert to VCF because we cannot determine which field to use as the VCF N (name) field"];
                }
                if (!defined($fields_for{EMAIL})) {
                    log_warn "We cannot determine which field to use as the VCF EMAIL field";
                }
                if (!defined($fields_for{CELL})) {
                    log_warn "We cannot determine which field to use as the VCF CELL (cellular phone) field";
                }
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
                        next unless exists $field_idxs{$field};
                        $row->[$field_idxs{$field}] = $_->{$field};
                    }
                }
            }
            $res .= _get_csv_row($csv_emitter, $row, $i, $outputs_header);
        } elsif ($action eq 'add-fields') {
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
                    return [400, "Field '$args{before}' (to add new fields before) not found"]
                        unless defined $field_idx;
                } elsif (defined $args{after}) {
                    for (0..$#{$row}) {
                        if ($row->[$_] eq $args{after}) {
                            $field_idx = $_+1;
                            last;
                        }
                    }
                    return [400, "Field '$args{after}' (to add new fields after) not found"]
                        unless defined $field_idx;
                } else {
                    $field_idx = @$row;
                }
                splice @$row, $field_idx, 0, @{ $args{fields} };
                for (keys %field_idxs) {
                    if ($field_idxs{$_} >= $field_idx) {
                        $field_idxs{$_}++;
                    }
                }
                $fields = $row;
            } else {
                unless ($code) {
                    $code = _compile($args{eval} // 'return');
                    if (!defined($args{fields}) || !@{ $args{fields} }) {
                        return [400, "Please specify one or more fields (-F)"];
                    }
                    for (@{ $args{fields} }) {
                        unless (length $_) {
                            return [400, "New field name cannot be empty"];
                        }
                        if (defined $field_idxs{$_}) {
                            return [412, "Field '$_' already exists"];
                        }
                    }
                }
                {
                    local $_ = $args{hash} ? _array2hash($row, $fields) : $row;
                    local $main::row = $row;
                    local $main::rownum = $i;
                    local $main::csv = $csv_parser;
                    local $main::field_idxs = \%field_idxs;
                    my @vals;
                    eval { @vals = $code->() };
                    die "Error while adding field(s) '".join(",", @{$args{fields}})."' for row #$i: $@\n"
                        if $@;
                    if (ref $vals[0] eq 'ARRAY') { @vals = @{ $vals[0] } }
                    splice @$row, $field_idx, 0,
                        (map { $_ // '' } @vals[0 .. $#{$args{fields}} ]);
                }
            }
            $res .= _get_csv_row($csv_emitter, $row, $i, $outputs_header);
        } elsif ($action eq 'delete-fields') {
            unless ($selected_fields) {
                my $res = _select_fields($fields, \%field_idxs, \%args);
                return $res unless $res->[0] == 100;
                $selected_fields = $res->[2][0];
                $selected_field_idxs_array = $res->[2][1];
                return [412, "At least one field must remain"] if @$selected_fields == @$fields;
                $selected_field_idxs_array_sorted = [sort { $b <=> $a } @$selected_field_idxs_array];
            }
            for (@$selected_field_idxs_array_sorted) {
                splice @$row, $_, 1;
            }
            $res .= _get_csv_row($csv_emitter, $row, $i, $outputs_header);
        } elsif ($action eq 'select-fields') {
            unless ($selected_fields) {
                my $res = _select_fields($fields, \%field_idxs, \%args);
                return $res unless $res->[0] == 100;
                $selected_fields = $res->[2][0];
                return [412, "At least one field must be selected"] unless @$selected_fields;
                $selected_field_idxs_array = $res->[2][1];
            }
            $row = [@{$row}[@$selected_field_idxs_array]];
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
        } elsif ($action eq 'freqtable') {
            if ($i == 1) {
            } else {
                $field_idx = _get_field_idx($args{field}, \%field_idxs);
                $freqtable{ $row->[$field_idx] }++;
            }
        } elsif ($action eq 'select-rows') {
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
                binmode $split_fh, ":encoding(utf8)";
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
        } elsif ($action eq 'pick-rows') {
            if ($i > 1) {
                if ($args{pick_num} == 1) {
                    # algorithm from Learning Perl
                    $rows->[0] = $row if rand($i-1) < 1;
                } else {
                    # algorithm from Learning Perl, modified
                    if (@$rows < $args{pick_num}) {
                        # we haven't reached $pick_num, put row to result in a
                        # random position
                        splice @$rows, rand(@$rows+1), 0, $row;
                    } else {
                        # we have reached $pick_num, just replace an item
                        # randomly, using algorithm from Learning Perl, slightly
                        # modified
                        rand($i-1) < @$rows and splice @$rows, rand(@$rows), 1, $row;
                    }
                }
            }
        } elsif ($action eq 'transpose') {
            push @$rows, $row;
        } elsif ($action eq 'convert-to-hash') {
            if ($i == $args{_row_number}) {
                $selected_row = $row;
            }
        } elsif ($action eq 'convert-to-td') {
            push @$rows, $row unless $i == 1;
        } elsif ($action eq 'fill-template') {
            push @$rows, _array2hash($row, $fields) unless $i == 1;
        } elsif ($action eq 'get-cells') {
            my $j = -1;
          COORD:
            for my $coord (@{ $args{coordinates} }) {
                $j++;
                my ($coord_col, $coord_row) = $coord =~ /\A(.+),(.+)\z/
                    or return [400, "Invalid coordinate '$coord': must be in col,row form"];
                $coord_row =~ /\A[0-9]+\z/
                    or return [400, "Invalid coordinate '$coord': invalid row syntax '$coord_row', must be a number"];
                next COORD unless $i == $coord_row;
                if ($coord_col =~ /\A[0-9]+\z/) {
                    $coord_col >= 0 && $coord_col < @$fields-1
                        or return [400, "Invalid coordinate '$coord': column number '$coord_col' out of bound, must be between 0-".(@$fields-1)];
                    $cells[$j] = $row->[$coord_col];
                } else {
                    exists $field_idxs{$coord_col}
                        or return [400, "Invalid coordinate '$coord': Unknown column name '$coord_col'"];
                    $cells[$j] = $row->[$field_idxs{$coord_col}];
                }
            }
        } elsif ($action eq 'convert-to-vcf') {
            unless ($i == 1) {
                my $vcard = join(
                    "",
                    "BEGIN:VCARD\n",
                    "VERSION:3.0\n",
                    "N:", $row->[$field_idxs{ $fields_for{N} }], "\n",
                    (defined $fields_for{EMAIL} ? ("EMAIL;type=INTERNET;type=WORK;pref:", $row->[$field_idxs{ $fields_for{EMAIL} }], "\n") : ()),
                    (defined $fields_for{CELL} ? ("TEL;type=CELL:", $row->[$field_idxs{ $fields_for{CELL} }], "\n") : ()),
                    "END:VCARD\n\n",
                );
                push @$rows, $vcard;
            }
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

    if ($action eq 'convert-to-hash') {
        return [200, "OK", join("", @$rows)];
    }

    if ($action eq 'convert-to-td') {
        return [200, "OK", $rows, {'table.fields'=>$fields}];
    }

    if ($action eq 'convert-to-vcf') {
        return [200, "OK", join("", @$rows)];
    }

    if ($action eq 'freqtable') {
        my @freqtable;
        for (sort { $freqtable{$b} <=> $freqtable{$a} } keys %freqtable) {
            push @freqtable, [$_, $freqtable{$_}];
        }
        return [200, "OK", \@freqtable, {'table.fields'=>['value','freq']}];
    }

    if ($action eq 'pick-rows') {
        if ($has_header) {
            $csv_emitter->combine(@$fields);
            $res .= $csv_emitter->string . "\n";
        }
        for my $row (@$rows) {
            $res .= _get_csv_row($csv_emitter, $row, $i, $outputs_header);
        }
    }

    if ($action eq 'sort-rows') {

        # whether we should compute keys
        my @keys;
        if ($args{sort_key}) {
            my $code_gen_key = _compile($args{sort_key});
            if ($action eq 'sort-rows') {
                for my $row (@$rows) {
                    local $_ = $args{hash} ? _array2hash($row, $fields) : $row;
                    push @keys, $code_gen_key->($_);
                }
            } else {
                # sort-fields
                for my $field (@$fields) {
                    local $_ = $field;
                    push @keys, $code_gen_key->($_);
                }
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
            } else {
                if ($args{hash}) {
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
            }

            if (@keys) {
                # sort indices according to keys first, then return sorted
                # rows according to indices
                my @sorted_indices = sort { local $main::a=$a; local $main::b=$b; $code->($main::a,$main::b) } 0..$#{$rows};
                $rows = [map {$rows->[$_]} @sorted_indices];
            } else {
                $rows = [sort { local $main::a=$a; local $main::b=$b; $code->($main::a,$main::b) } @$rows];
            }

        } elsif ($args{sort_by_fields}) {

            my @fields;
            my $code_str = "";
            for my $field_spec (@{ $args{sort_by_fields} }) {
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

        # output csv
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

    if ($action eq 'get-cells') {
        if (@{ $args{coordinates} } == 1) {
            return [200, "OK", $cells[0]];
        } else {
            return [200, "OK", \@cells];
        }
    }

    if ($action eq 'fill-template') {
        require File::Slurper::Dash;

        my $output = '';
        my $template = File::Slurper::Dash::read_text($args{template_filename});
        for my $row (@$rows) {
            my $text = $template;
            $text =~ s/\[\[(.+?)\]\]/defined $row->{$1} ? $row->{$1} : "[[UNDEFINED:$1]]"/eg;
            $output .= (length $output ? "\n---\n" : "") . $text;
        }
        return [200, "OK", $output];
    }

    _return_or_write_file([200, "OK", $res, {"cmdline.skip_format"=>1}], $args{output_filename}, $args{overwrite});
} # csvutil

our $common_desc = <<'_';
*Common notes for the utilities*

Encoding: The utilities in this module/distribution accept and emit UTF8 text.

_

$SPEC{csv_add_fields} = {
    v => 1.1,
    summary => 'Add one or more fields to CSV file',
    description => <<'_' . $common_desc,

The new fields by default will be added at the end, unless you specify one of
`--after` (to put after a certain field), `--before` (to put before a certain
field), or `--at` (to put at specific position, 1 means the first field). The
new fields will be clustered together though, you currently cannot set the
position of each new field. But you can later reorder fields using
<prog:csv-sort-fields>.

If supplied, your Perl code (`-e`) will be called for each row (excluding the
header row) and should return the value for the new fields (either as a list or
as an arrayref). `$_` contains the current row (as arrayref, or if you specify
`-H`, as a hashref). `$main::row` is available and contains the current row
(always as an arrayref). `$main::rownum` contains the row number (2 means the
first data row). `$csv` is the <pm:Text::CSV_XS> object. `$main::field_idxs` is
also available for additional information.

If `-e` is not supplied, the new fields will be getting the default value of
empty string (`''`).

_
    args => {
        %argspecs_csv_input,
        %argspecs_csv_output,
        %argspecopt_input_filename_0,
        %argspecopt_output_filename,
        %argspecopt_overwrite,
        %argspec_fields_1plus_nocomp,
        %argspecopt_eval,
        %argspec_hash,
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
                '(1 means first field)',
            schema => ['int*', min=>1],
        },
    },
    args_rels => {
        choose_one => [qw/after before at/],
    },
    examples => [
        {
            summary => 'Add a few new blank fields at the end',
            argv => ['file.csv', 'field4', 'field6', 'field5'],
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'Add a few new blank fields after a certain field',
            argv => ['file.csv', 'field4', 'field6', 'field5', '--after', 'field2'],
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'Add a new field and set its value',
            argv => ['file.csv', 'after_tax', '-e', '$main::row->[5] * 1.11'],
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'Add a couple new fields and set their values',
            argv => ['file.csv', 'tax_rate', 'after_tax', '-e', '(0.11, $main::row->[5] * 1.11)'],
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],
    tags => ['outputs_csv'],
};
sub csv_add_fields {
    my %args = @_;
    csvutil(
        %args, action=>'add-fields',
        _after  => $args{after},
        _before => $args{before},
        _at     => $args{at},
    );
}

$SPEC{csv_list_field_names} = {
    v => 1.1,
    summary => 'List field names of CSV file',
    args => {
        %argspecs_csv_input,
        %argspecopt_input_filename_0,
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
        %argspecs_csv_input,
        %argspecopt_input_filename_0,
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
        %argspecs_csv_input,
        %argspecs_csv_output,
        %argspecopt_input_filename_0,
        %argspecsopt_field_selection,
        %argspecopt_output_filename_1,
        %argspecopt_overwrite,
    },
    description => '' . $common_desc,
    tags => ['outputs_csv'],
};
sub csv_delete_fields {
    my %args = @_;
    csvutil(%args, action=>'delete-fields');
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

To munge multiple fields, use <prog:csv-munge-row>.

_
    args => {
        %argspecs_csv_input,
        %argspecs_csv_output,
        %argspecopt_input_filename_0,
        %argspecopt_output_filename,
        %argspecopt_overwrite,
        %argspec_field_1,
        %argspec_eval_2,
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

You can also munge a single field using <prog:csv-munge-field>.

You cannot add new fields using this utility. To do so, use
<prog:csv-add-fields>.

_
    args => {
        %argspecs_csv_input,
        %argspecs_csv_output,
        %argspecopt_input_filename_0,
        %argspecopt_output_filename,
        %argspecopt_overwrite,
        %argspec_eval_1,
        %argspec_hash,
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
        %argspecs_csv_input,
        %argspecs_csv_output,
        %argspecopt_input_filename_0,
        %argspecopt_output_filename,
        %argspecopt_overwrite,
        %argspecopt_output_filename_1,
        %argspecopt_overwrite,
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

    my $csv_parser  = _instantiate_parser(\%args, 'input_');
    my $csv_emitter = _instantiate_emitter(\%args);

    my ($fh, $err) = _open_file_read($args{input_filename});

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

    _return_or_write_file([200, "OK", $res, {"cmdline.skip_format"=>1}], $args{output_filename}, $args{overwrite});
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

Example output CSV (using `--by-field +age` which means by age numerically and
ascending):

    name,age
    Dennis,15
    Andy,20
    Ben,30
    Jerry,30

Example output CSV (using `--by-field -age`, which means by age numerically and
descending):

    name,age
    Ben,30
    Jerry,30
    Andy,20
    Dennis,15

Example output CSV (using `--by-field name`, which means by name ascibetically
and ascending):

    name,age
    Andy,20
    Ben,30
    Dennis,15
    Jerry,30

Example output CSV (using `--by-field ~name`, which means by name ascibetically
and descending):

    name,age
    Jerry,30
    Dennis,15
    Ben,30
    Andy,20

Example output CSV (using `--by-field +age --by-field ~name`):

    name,age
    Dennis,15
    Andy,20
    Jerry,30
    Ben,30

You can also reverse the sort order (`-r`) or sort case-insensitively (`-i`).

For more flexibility, instead of `--by-field` you can use `--by-code`:

Example output `--by-code '$a->[1] <=> $b->[1] || $b->[0] cmp $a->[0]'` (which
is equivalent to `--by-field +age --by-field ~name`):

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
        %argspecs_csv_input,
        %argspecs_csv_output,

        %argspecopt_input_filename_0,
        %argspecopt_output_filename_1,
        %argspecopt_overwrite,
        %argspec_hash,

        %argspecs_sort_rows_short,
    },
    args_rels => {
        req_one => ['by_fields', 'by_code', 'by_sortsub'],
    },
    tags => ['outputs_csv'],
};
sub csv_sort_rows {
    my %args = @_;

    my %csvutil_args = (
        hash_subset(\%args, \%argspecs_csv_input, \%argspecs_csv_output),
        action => 'sort-rows',

        input_filename => $args{input_filename},
        output_filename => $args{output_filename},
        overwrite => $args{overwrite},
        hash => $args{hash},

        sort_reverse => $args{reverse},
        sort_ci => $args{ci},
        sort_key => $args{key},
        sort_by_fields => $args{by_fields},
        sort_by_code   => $args{by_code},
        sort_by_sortsub => $args{by_sortsub},
        sort_sortsub_args => $args{sortsub_args},
    );

    csvutil(%csvutil_args);
}

$SPEC{csv_shuf_rows} = {
    v => 1.1,
    summary => 'Shuffle CSV rows',
    description => <<'_' . $common_desc,

This is basically like Unix command `shuf` except it does not shuffle the header
row.

_
    args => {
        %argspecs_csv_input,
        %argspecs_csv_output,
        %argspecopt_input_filename_0,
        %argspecopt_output_filename_1,
        %argspecopt_overwrite,
    },
    tags => ['outputs_csv'],
};
sub csv_shuf_rows {
    my %args = @_;
    csvutil(
        %args,
        action => 'sort-rows',
        # TODO: this feels less shuffled
        sort_by_code => sub { int(rand 3)-1 }, # return -1,0,1 randomly
    );
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
provides the ordering example, e.g. `--by-examples-json '["a","c","b"]'`, or use
`--by-code` or `--by-sortsub`.

_
    args => {
        %argspecs_csv_input,
        %argspecs_csv_output,

        %argspecopt_input_filename_0,
        %argspecopt_output_filename_1,
        %argspecopt_overwrite,

        %argspecs_sort_fields_short,
    },
    tags => ['outputs_csv'],
};
sub csv_sort_fields {
    my %args = @_;

    my %csvutil_args = (
        hash_subset(\%args, \%argspecs_csv_input, \%argspecs_csv_output),
        action => 'sort-fields',

        input_filename => $args{input_filename},
        output_filename => $args{output_filename},
        overwrite => $args{overwrite},

        sort_reverse => $args{reverse},
        sort_ci => $args{ci},
        (sort_examples => $args{by_examples}) x !!defined($args{by_examples}),
        (sort_by_code => $args{by_code}) x !!defined($args{by_code}),
        (sort_by_sortsub => $args{by_sortsub}) x !!defined($args{by_sortsub}),
    );
    csvutil(%csvutil_args);
}

$SPEC{csv_shuf_fields} = {
    v => 1.1,
    summary => 'Shuffle CSV fields',
    description => <<'_' . $common_desc,

_
    args => {
        %argspecs_csv_input,
        %argspecs_csv_output,
        %argspecopt_input_filename_0,
        %argspecopt_output_filename_1,
        %argspecopt_overwrite,
    },
    tags => ['outputs_csv'],
};
sub csv_shuf_fields {
    my %args = @_;
    csvutil(
        %args,
        action => 'sort-fields',
        # TODO: this feels less shuffled
        sort_by_code => sub { int(rand 3)-1 }, # return -1,0,1 randomly
    );
}

$SPEC{csv_sum} = {
    v => 1.1,
    summary => 'Output a summary row which are arithmetic sums of data rows',
    args => {
        %argspecs_csv_input,
        %argspecs_csv_output,
        %argspecopt_input_filename_0,
        %argspecopt_output_filename_1,
        %argspecopt_overwrite,
        %argspec_with_data_rows,
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
        %argspecs_csv_input,
        %argspecs_csv_output,
        %argspecopt_input_filename_0,
        %argspecopt_output_filename_1,
        %argspecopt_overwrite,
        %argspec_with_data_rows,
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
        %argspecs_csv_input,
        %argspecopt_input_filename_0,
        %argspec_field_1,
    },
    description => '' . $common_desc,
};
sub csv_freqtable {
    my %args = @_;

    csvutil(%args, action=>'freqtable');
}

$SPEC{csv_select_rows} = {
    v => 1.1,
    summary => 'Only output specified row(s)',
    args => {
        %argspecs_csv_input,
        %argspecs_csv_output,
        %argspecopt_input_filename_0,
        %argspecopt_output_filename_1,
        %argspecopt_overwrite,
        row_spec => {
            schema => 'str*',
            summary => 'Row number (e.g. 2 for first data row), '.
                'range (2-7), or comma-separated list of such (2-7,10,20-23)',
            req => 1,
            pos => 2,
        },
    },
    description => '' . $common_desc,
    links => [
        {url=>"prog:csv-split"},
    ],
    tags => ['outputs_csv'],
};
sub csv_select_rows {
    my %args = @_;

    csvutil(%args, action=>'select-rows');
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
        %argspecs_csv_input,
        %argspecs_csv_output,
        %argspecopt_input_filename_0,
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
        {url=>"prog:csv-select-rows"},
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
        %argspecs_csv_input,
        %argspecs_csv_output,
        %argspecopt_input_filename_0,
        %argspecopt_output_filename_1,
        %argspecopt_overwrite,
        %argspec_eval,
        %argspec_hash,
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

$SPEC{csv_pick_rows} = {
    v => 1.1,
    summary => 'Return one or more random rows from CSV',
    args => {
        %argspecs_csv_input,
        %argspecs_csv_output,
        %argspecopt_input_filename_0,
        %argspecopt_output_filename_1,
        %argspecopt_overwrite,
        num => {
            summary => 'Number of rows to pick',
            schema => 'posint*',
            default => 1,
            cmdline_aliases => {n=>{}},
        },
    },
    description => '' . $common_desc,
    tags => ['outputs_csv'],
};
sub csv_pick_rows {
    my %args = @_;
    csvutil(
        %args,
        action=>'pick-rows',
        pick_num => $args{num} // 1,
    );
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
        %argspecs_csv_input,
        %argspecopt_input_filename_0,
        %argspecopt_output_filename_1,
        %argspecopt_overwrite,
        %argspec_eval,
        %argspec_hash,
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
        %argspecs_csv_input,
        %argspecopt_input_filename_0,
        %argspec_eval,
        %argspec_hash,
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
        %argspecs_csv_input,
        %argspecopt_input_filename_0,
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
        %argspecs_csv_input,
        %argspecs_csv_output,
        %argspecopt_input_filename_0,
        %argspecopt_output_filename_1,
        %argspecopt_overwrite,
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
        %argspecs_csv_input,
        %argspecopt_input_filename_0,
    },
    description => '' . $common_desc,
};
sub csv2td {
    my %args = @_;

    csvutil(%args, action=>'convert-to-td');
}

$SPEC{csv2vcf} = {
    v => 1.1,
    summary => 'Create a VCF from selected fields of the CSV',
    description => <<'_',

You can set which CSV fields to use for name, cell phone, and email. If unset,
will guess from the field name. If that also fails, will warn/bail out.

_
    args => {
        %argspecs_csv_input,
        %argspecopt_input_filename_0,
        %argspecsopt_vcf,
    },
    description => '' . $common_desc,
};
sub csv2vcf {
    my %args = @_;

    csvutil(%args, action=>'convert-to-vcf');
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
        %argspecs_csv_input,
        %argspecs_csv_output,
        %argspecopt_input_filenames_0plus,
        %argspecopt_output_filename,
        %argspecopt_overwrite,
    },
    tags => ['outputs_csv'],
};
sub csv_concat {
    my %args = @_;

    my %res_field_idxs;
    my @rows;

    for my $input_filename (@{ $args{input_filenames} }) {
        my $csv_parser  = _instantiate_parser(\%args, 'input_');

        my ($fh, $err) = _open_file_read($input_filename);
        return $err if $err;

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
                if ($j >= @$fields) {
                    log_warn "File %s line %d contains more than %d fields, skipped", $input_filename, $i, scalar(@$fields);
                    last;
                }
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
    _return_or_write_file([200, "OK", $res, {"cmdline.skip_format"=>1}], $args{output_filename}, $args{overwrite});
}

$SPEC{csv_select_fields} = {
    v => 1.1,
    summary => 'Only output selected field(s)',
    args => {
        %argspecs_csv_input,
        %argspecs_csv_output,
        %argspecopt_input_filename_0,
        %argspecopt_output_filename_1,
        %argspecopt_overwrite,
        %argspecsopt_field_selection,
    },
    description => '' . $common_desc,
    tags => ['outputs_csv'],
};
sub csv_select_fields {
    my %args = @_;
    csvutil(%args, action=>'select-fields');
}

$SPEC{csv_pick_fields} = {
    v => 1.1,
    summary => 'Select one or more random fields from CSV',
    args => {
        %argspecs_csv_input,
        %argspecs_csv_output,
        %argspecopt_input_filename_0,
        %argspecopt_output_filename_1,
        %argspecopt_overwrite,
        num => {
            summary => 'Number of fields to pick',
            schema => 'posint*',
            default => 1,
            cmdline_aliases => {n=>{}},
        },
    },
    description => '' . $common_desc,
    tags => ['outputs_csv'],
};
sub csv_pick_fields {
    my %args = @_;
    csvutil(
        %args,
        action=>'select-fields',
        pick_num => $args{num} // 1,
    );
}

$SPEC{csv_get_cells} = {
    v => 1.1,
    summary => 'Get one or more cells from CSV',
    args => {
        %argspecs_csv_input,
        %argspecopt_input_filename_0,
        coordinates => {
            'x.name.is_plural' => 1,
            'x.name.singular' => 'coordinate',
            summary => 'List of coordinates, each in the form of <col>,<row> e.g. colname,0 or 1,1',
            schema => ['array*', of=>'str*'],
            pos => 1,
            slurpy => 1,
        },
    },
    description => <<'_' . $common_desc,

This utility lets you specify "coordinates" of cell locations to extract. Each
coordinate is in the form of `<col>,<row>` where `<col>` is the column name or
position (zero-based, so 0 is the first column) and `<row>` is the row position
(one-based, so 1 is the header row and 2 is the first data row).

_
};
sub csv_get_cells {
    my %args = @_;
    csvutil(%args, action=>'get-cells');
}

$SPEC{csv_fill_template} = {
    v => 1.1,
    summary => 'Substitute template values in a text file with fields from CSV rows',
    args => {
        %argspecs_csv_input,
        %argspecopt_input_filename_0,
        %argspecopt_output_filename_1,
        %argspecopt_overwrite,
        template_filename => {
            schema => 'filename*',
            req => 1,
            pos => 2,
        },
        # XXX whether to output multiple files or combined
        # XXX row selection?
    },
    description => <<'_' . $common_desc,

Templates are text that contain `[[NAME]]` field placeholders. The field
placeholders will be replaced by values from the CSV file. This is a simple
alternative to mail-merge. (I first wrote this utility because LibreOffice
Writer, as always, has all the annoying bugs; that particular time, one that
prevented mail merge from working.)

Example:

    % cat madlib.txt
    Today I went to the park. I saw a(n) [[adjective1]] [[noun1]] running
    towards me. It looked hungry, really hungry. Horrified and terrified, I took
    a(n) [[adjective2]] [[noun2]] and waved the thing [[adverb1]] towards it.
    [[adverb2]], when it arrived at my feet, it [[verb1]] and [[verb2]] me
    instead. I was relieved, the [[noun1]] was a friendly creature after all.
    After we [[verb3]] for a little while, I went home with a(n) [[noun3]] on my
    face. That was an unforgettable day indeed.

    % cat values.csv
    adjective1,adjective2,adjective3,noun1,noun2,noun3,verb1,verb2,verb3,adverb1,adverb2
    slow,gigantic,sticky,smartphone,six-wheeler truck,lollipop,piece of tissue,threw,kissed,stared,angrily,hesitantly
    sweet,delicious,red,pelican,bottle of parfume,desk,exercised,jumped,slept,confidently,passively

    % csv-fill-template values.csv - madlib.txt
    Today I went to the park. I saw a(n) slow six-wheeler truck running
    towards me. It looked hungry, really hungry. Horrified and terrified, I took
    a(n) gigantic lollipop and waved the thing angrily towards it.
    hesitantly, when it arrived at my feet, it threw and kissed me
    instead. I was relieved, the six-wheeler truck was a friendly creature after all.
    After we stared for a little while, I went home with a(n) piece of tissue on my
    face. That was an unforgettable day indeed.

    ---
    Today I went to the park. I saw a(n) sweet pelican running
    towards me. It looked hungry, really hungry. Horrified and terrified, I took
    a(n) delicious bottle of parfume and waved the thing confidently towards it.
    passively, when it arrived at my feet, it exercised and jumped me
    instead. I was relieved, the pelican was a friendly creature after all.
    After we slept for a little while, I went home with a(n) desk on my
    face. That was an unforgettable day indeed.

_
};
sub csv_fill_template {
    my %args = @_;
    csvutil(%args, action=>'fill-template');
}

$SPEC{csv_setop} = {
    v => 1.1,
    summary => 'Set operation (union/unique concatenation of rows, intersection/common rows, difference of rows) against several CSV files',
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
        %argspecs_csv_input,
        %argspecs_csv_output,
        %argspecopt_input_filenames_0plus,
        %argspecopt_output_filename,
        %argspecopt_overwrite,
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
    my $num_files = @{ $args{input_filenames} };

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
    for my $input_filename (@{ $args{input_filenames} }) {
        my $csv = _instantiate_parser(\%args, 'input_');

        my ($fh, $err) = _open_file_read($input_filename);
        return $err if $err;

        my $i = 0;
        my @data_rows;
        my $field_idxs = {};
        while (my $row = $csv->getline($fh)) {
            $i++;
            if ($i == 1) {
                if ($args{input_header} // 1) {
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
    } # for each input_filename

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

    _return_or_write_file([200, "OK", $res, {"cmdline.skip_format"=>1}], $args{output_filename}, $args{overwrite});
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
        %argspecs_csv_input,
        %argspecs_csv_output,
        %argspecopt_output_filename,
        %argspecopt_overwrite,
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
        my $csv = _instantiate_parser(\%args, 'input_');

        my ($fh, $err) = _open_file_read($args{source});
        return $err if $err;

        my $i = 0;
        while (my $row = $csv->getline($fh)) {
            $i++;
            if ($i == 1) {
                if ($args{input_header} // 1) {
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
        my $csv = _instantiate_parser(\%args, 'input_');

        my ($fh, $err) = _open_file_read($args{target});
        return $err if $err;

        my $i = 0;
        while (my $row = $csv->getline($fh)) {
            $i++;
            if ($i == 1) {
                if ($args{input_header} // 1) {
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
        _return_or_write_file([200, "OK", $res, {"cmdline.skip_format"=>1}], $args{output_filename}, $args{overwrite});
    }
}

$SPEC{gen_csv_util} = {
    v => 1.1,
    summary => 'Generate a CSV utility',
    description => <<'_',

This routine is used to generate a CSV utility in the form of a <pm:Rinci>
function (code and metadata). You can then produce a CLI from the Rinci function
simply using <pm:Perinci::CmdLine::Gen> or, if you use <pm:Dist::Zilla>,
<pm:Dist::Zilla::Plugin::GenPericmdScript> or, if on the command-line,
<prog:gen-pericmd-script>.

To create a CSV utility, you specify a `name` (e.g. `csv_dump`; must be a valid
unqualified Perl identifier/function name) and optionally `summary`,
`description`, and other metadata like `links` or even `add_metadata_props`.
Then you specify one or more of `on_*` arguments to supply behaviors (coderef)
for your CSV utility at various hook points.


*THE HOOKS*

All code for hooks should accept a single argument `r`. `r` is a stash (hashref)
of various data, the keys of which will depend on which hook point being called.
You can also add more keys to store data.

The order of the hooks, in processing chronological order:

* on_begin

  Called when utility begins, before reading CSV. You can use this hook e.g. to
  process arguments, set output filenames (if you allow custom output
  filenames).

* before_read_input

  Called before opening any input CSV file. This hook is *still* called even if
  your utility sets `accepts_csv` to false.

  At this point, the `input_filenames` stash key has not been set. You can use
  this hook e.g. to set a custom `input_filenames`.

* before_open_input_file

  Called before an input CSV file is about to be opene, including for stdin
  (`-`). You can use this hook e.g. to check/preprocess input file.

* after_open_input_file

  Called after each input CSV file is opened, including for stdin (`-`). You can
  use this hook e.g. to check/preprocess input file.

* on_input_header_row

  Called when receiving header row (called for every input file, and called even
  when user specify `--no-input-header`, in which case the header row will be
  the generated `["field1", "field2", ...]`. You can use this hook e.g. to
  add/remove/rearrange fields.

* on_input_data_row

  Called when receiving each data row. You can use this hook e.g. to modify the
  row or print output (for line-by-line transformation or filtering).

* after_read_input

  Called after the last row of the last CSV file is read and the last file is
  closed. This hook is *still* called, if you do not set `accepts_csv` option.
  At this point the stash keys related to CSV reading have all been cleared,
  including `input_filenames`, `input_filename`, `input_fh`, etc.

  You can use this hook e.g. to print output if you buffer the output.

* on_end

  Called when utility is about to exit. You can use this hook e.g. to return the
  final result.


*THE STASH*

The common keys that `r` will contain:

- `gen_args`, hash. The arguments used to generate the CSV utility.

- `util_args`, hash. The arguments that your CSV utility accepts. Parsed from
  command-line arguments (or configuration files, or environment variables).

- `name`, str. The name of the CSV utility. Which can also be retrieved via
  `gen_args`.

If you are accepting CSV data, the following keys will also be available (in
`on_input_header_row` and `on_input_data_row` hooks):

- `input_parser`, a <pm:Text::CSV_XS> instance for input parsing.

- `input_filenames`, array of str.

- `input_filename`, str. The name of the current input file being read (`-` if
  reading from stdin).

- `input_filenum`, uint. The number of the current input file, 1 being the first
  file, 2 for the second, and so on.

- `input_fh`, the handle to the current file being read.

- `input_rownum`, uint. The number of rows that have been read (reset after each
  input file).

- `input_data_rownum`, uint. The number of data rows that have been read (reset
  after each input file). This will be equal to `input_rownum` less 1 if input
  file has header.

- `input_row`, aos (array of str). The current input CSV row as an arrayref.

- `input_row_as_hashref`, hos (hash of str). The current input CSV row as a
  hashref, with field names as hash keys and field values as hash values. This
  will only be calculated if utility wants it. Utility can express so by setting
  C<< $r->{wants_input_row_as_hashref} >> to true, e.g. in the `on_begin` hook.

- `input_header_row_count`, uint. Contains the number of actual header rows that
  have been read. If CLI user specifies `--no-input-header`, this will stay at
  0. Will be reset for each CSV file.

- `input_data_row_count`, int. Contains the number of actual data rows that have
  read. Will be reset for each CSV file.

If you are outputting CSV, the following keys will be available:

- `output_emitter`, a <pm:Text::CSV_XS> instance for output.

- `output_filenames`, array of str.

- `output_filename`, str, name of current output file.

- `output_filenum`, uint, the number of the current output file, 1 being the
  first file, 2 for the second, and so on.

- `output_fh`, handle to the current output file.

- `output_rownum`, uint. The number of rows that have been outputted (reset
  after each output file).

- `output_data_rownum`, uint. The number of data rows that have been outputted
  (reset after each output file). This will be equal to `input_rownum` less 1 if
  input file has header.

For other hook-specific keys, see the documentation for associated hook point.


*READING CSV DATA*

To read CSV data, normally your utility would provide handler for the
`on_input_data_row` hook and sometimes additionally `on_input_header_row`.


*OUTPUTTING CSV DATA*

To output CSV data, you first specify `outputs_csv` (or `outputs_multiple_csv`)
option to true. Then, to print a CSV row, you call the C<< $r->{code_printline}
>>, passing the row you want to output as argument. An arrayref or hashref is
accepted. Often, for line-by-line transformation utilities, you do this in the
`on_input_data_row` hook. But you can also

*CHANGING THE OUTPUT FIELDS*


*READING MULTIPLE CSV FILES*


*OUTPUTTING TO MULTIPLE CSV FILES*


_
    args => {
        name => {
            schema => 'perl::identifier::unqualified_ascii*',
            req => 1,
            tags => ['category:metadata'],
        },
        summary => {
            schema => 'str*',
            tags => ['category:metadata'],
        },
        description => {
            schema => 'str*',
            tags => ['category:metadata'],
        },
        links => {
            schema => ['array*', of=>'hash*'], # XXX defhashes
            tags => ['category:metadata'],
        },
        examples => {
            schema => ['array*'], # defhashes
            tags => ['category:metadata'],
        },
        add_meta_props => {
            summary => 'Add additional Rinci function metadata properties',
            schema => ['hash*'],
            tags => ['category:metadata'],
        },
        add_args => {
            schema => ['hash*'],
            tags => ['category:metadata'],
        },
        add_args_rels => {
            schema => ['hash*'],
            tags => ['category:metadata'],
        },

        accepts_csv => {
            summary => 'Whether utility accepts CSV data',
            'summary.alt.bool.not' => 'Specify that utility does not accept CSV data',
            schema => 'bool*',
            default => 1,
        },
        accepts_multiple_csv => {
            summary => 'Whether utility accepts CSV data',
            schema => 'bool*',
            description => <<'_',

Setting this option to true will implicitly set the `accepts_csv` option to
true, obviously.

_
        },
        outputs_csv => {
            summary => 'Whether utility outputs CSV data',
            'summary.alt.bool.not' => 'Specify that utility does not output CSV data',
            schema => 'bool*',
            default => 1,
        },
        outputs_multiple_csv => {
            summary => 'Whether utility outputs CSV data',
            schema => 'bool*',
            description => <<'_',

Setting this option to true will implicitly set the `outputs_csv` option to
true, obviously.

_
        },

        on_begin => {
            schema => 'code*',
        },
        before_read_input => {
            schema => 'code*',
        },
        before_open_input_file => {
            schema => 'code*',
        },
        after_open_input_file => {
            schema => 'code*',
        },
        on_input_header_row => {
            schema => 'code*',
        },
        on_input_data_row => {
            schema => 'code*',
        },
        before_close_input_file => {
            schema => 'code*',
        },
        after_close_input_file => {
            schema => 'code*',
        },
        after_read_input => {
            schema => 'code*',
        },
        on_input_data_row => {
            schema => 'code*',
        },
        on_end => {
            schema => 'code*',
        },
    },
    result_naked => 1,
    result => {
        schema => 'bool*',
    },
};
sub gen_csv_util {
    my %gen_args = @_;

    my $name = delete($gen_args{name}) or die "Please specify name";
    my $summary = delete($gen_args{summary}) // '(No summary)';
    my $description = delete($gen_args{description}) // '(No description)';
    my $links = delete($gen_args{links}) // [];
    my $examples = delete($gen_args{examples}) // [];
    my $add_meta_props = delete $gen_args{add_meta_props};
    my $add_args = delete $gen_args{add_args};
    my $add_args_rels = delete $gen_args{add_args_rels};
    my $accepts_multiple_csv = delete($gen_args{accepts_multiple_csv});
    my $accepts_csv = delete($gen_args{accepts_csv}) // 1;
    $accepts_csv = 1 if $accepts_multiple_csv;
    my $outputs_multiple_csv = delete($gen_args{outputs_multiple_csv});
    my $outputs_csv = delete($gen_args{outputs_csv}) // 1;
    $accepts_csv = 1 if $accepts_multiple_csv;
    my $on_begin            = delete $gen_args{on_begin};
    my $before_read_input   = delete $gen_args{before_read_input};
    my $before_open_input_file = delete $gen_args{before_open_input_file};
    my $after_open_input_file  = delete $gen_args{after_open_input_file};
    my $on_input_header_row = delete $gen_args{on_input_header_row};
    my $on_input_data_row   = delete $gen_args{on_input_data_row};
    my $after_read_input    = delete $gen_args{after_read_input};
    my $on_end              = delete $gen_args{on_end};

    scalar(keys %gen_args) and die "Unknown argument(s): ".join(", ", keys %gen_args);

    my $code;
  CREATE_CODE: {
        $code = sub {
            my %util_args = @_;

            my $has_header = $util_args{input_header} // 1;
            my $outputs_header = $util_args{output_header} // $has_header;

            my $r = {
                gen_args => \%gen_args,
                util_args => \%util_args,
                name => $name,
            };

            # inside the main eval block, we call hook handlers. A handler can
            # throw an exception (which can be a string or an enveloped response
            # like [500, "some error message"], see Rinci::function). we trap
            # the exception so we can return the appropriate enveloped response.
          MAIN_EVAL:
            eval {

                if ($on_begin) {
                    log_trace "Calling on_begin hook handler ...";
                    $on_begin->($r);
                }

                if ($outputs_csv) {
                    my $output_emitter = _instantiate_emitter(\%util_args);
                    $r->{output_emitter} = $output_emitter;
                    $r->{has_printed_header} = 0;

                    my $code_printline = sub {
                        my $row = shift;

                        # set output filenames, if not yet
                        unless ($r->{output_filenames}) {
                            my @output_filenames;
                            if ($outputs_multiple_csv) {
                                @output_filenames = @{ $util_args{output_filenames} // ['-'] };
                            } else {
                                @output_filenames = ($util_args{output_filename} // '-');
                            }

                            $r->{output_filenames} = \@output_filenames;
                            $r->{output_num_of_files} //= scalar(@output_filenames);
                        } # set output filenames

                        # open the next file, if not yet
                        unless ($r->{output_fh} || $r->{wants_switch_to_next_output_file}) {
                            $r->{output_filenum} //= 0;
                            $r->{output_filenum}++;

                            $r->{output_rownum} = 0;
                            $r->{output_data_rownum} = 0;

                            # close the previous file, if any
                            if ($r->{output_fh} && $r->{output_filename} ne '-') {
                                log_debug "Closing output file '$r->{output_filename}' ...";
                                close $r->{output_fh} or die [500, "Can't close output file '$r->{output_filename}': $!"];
                                delete $r->{has_printed_header};
                                delete $r->{wants_switch_to_next_output_file};
                            }

                            # we have exhausted all the files, do nothing & return
                            return if $r->{output_filenum} > @{ $r->{output_filenames} };

                            $r->{output_filename} = $r->{output_filenames}[ $r->{output_filenum}-1 ];
                            log_info "[%d/%s] Opening output CSV file %s ...",
                                $r->{output_filenum}, $r->{output_num_of_files}, $r->{output_filename};
                            if ($r->{output_filename} eq '-') {
                                $r->{output_fh} = \*STDOUT;
                            } else {
                                if (-f $r->{output_filename}) {
                                    if ($r->{util_args}{overwrite}) {
                                        log_info "Will be overwriting output file %s", $r->{output_filename};
                                    } else {
                                        die [412, "Refusing to overwrite existing output file '$r->{output_filename}', choose another name or use --overwrite (-O)"];
                                    }
                                }
                                my ($fh, $err) = _open_file_write($r->{output_filename});
                                die $err if $err;
                                $r->{output_fh} = $fh;
                            }
                        } # open the next file

                        # set output fields, if not yet
                        unless ($r->{output_fields}) {
                            # by default, use the
                            $r->{output_fields} = $r->{input_fields};
                        }

                        # index the output fields, if not yet
                        unless ($r->{output_fields_idx}) {
                            $r->{output_fields_idx} = {};
                            for my $j (0 .. $#{ $r->{output_fields} }) {
                                $r->{output_fields_idx}{ $r->{output_fields}[$j] } = $j;
                            }
                        }

                        # print header line, if not yet
                        if ($outputs_header && !$r->{has_printed_header}) {
                            $r->{has_printed_header}++;
                            $r->{output_emitter}->print($r->{output_fh}, $r->{output_fields});
                            print { $r->{output_fh} } "\n";
                            $r->{output_rownum}++;
                        }

                        # print data line
                        if ($row) {
                            if (ref $row eq 'HASH') {
                                my $row0 = $row;
                                $row = [];
                                for my $j (0 .. $#{ $r->{output_fields} }) {
                                    $row->[$j] = $row0->{ $r->{output_fields}[$j] } // '';
                                }
                            }
                            $r->{output_emitter}->print( $r->{output_fh}, $row );
                            print { $r->{output_fh} } "\n";
                            $r->{output_rownum}++;
                            $r->{output_data_rownum}++;
                        }
                    }; # code_printline

                    $r->{code_printline} = $code_printline;
                } # if outputs csv

                if ($before_read_input) {
                    log_trace "Calling before_read_input handler ...";
                    $before_read_input->($r);
                }

              READ_CSV: {
                    last unless $accepts_csv;

                    my $input_parser = _instantiate_parser(\%util_args, 'input_');
                    $r->{input_parser} = $input_parser;

                    my @input_filenames;
                    if ($accepts_multiple_csv) {
                        @input_filenames = @{ $util_args{input_filenames} // ['-'] };
                    } else {
                        @input_filenames = ($util_args{input_filename} // '-');
                    }
                    $r->{input_filenames} //= \@input_filenames;

                    my $input_filenum = 0;
                    for my $input_filename (@input_filenames) {
                        $input_filenum++;
                        log_info "[file %d/%d] Reading input file %s ...",
                            $input_filenum, scalar(@input_filenames), $input_filename;
                        $r->{input_filenum} = $input_filenum;
                        $r->{input_filename} = $input_filename;

                        if ($before_open_input_file) {
                            log_trace "Calling before_open_input_file handler ...";
                            $before_open_input_file->($r);
                        }

                        my ($fh, $err) = _open_file_read($input_filename);
                        die $err if $err;
                        $r->{input_fh} = $fh;

                        if ($after_open_input_file) {
                            log_trace "Calling after_open_input_file handler ...";
                            $after_open_input_file->($r);
                        }

                        my $i;
                        $r->{input_header_row_count} = 0;
                        $r->{input_data_row_count} = 0;
                        $r->{input_fields} = []; # array, field names in order
                        $r->{input_field_idxs} = {}; # key=field name, value=index (0-based)
                        my $row0;
                        my $code_getline = sub {
                            if ($i == 0 && !$has_header) {
                                $row0 = $input_parser->getline($fh);
                                return unless $row0;
                                return [map { "field$_" } 1..@$row0];
                            } elsif ($i == 1 && !$has_header) {
                                $r->{input_data_row_count}++ if $row0;
                                return $row0;
                            }
                            my $res = $input_parser->getline($fh);
                            if ($res) {
                                $r->{input_header_row_count}++ if $i==0;
                                $r->{input_data_row_count}++ if $i;
                            }
                            $res;
                        };
                        $r->{code_getline} = $code_getline;

                        $i = 0;
                        while ($r->{input_row} = $code_getline->()) {
                            $i++;
                            $r->{input_rownum} = $i;
                            $r->{input_data_rownum} = $has_header ? $i-1 : $i;
                            if ($i == 1) {
                                # gather the list of fields
                                $r->{input_fields} = $r->{input_row};
                                $r->{orig_input_fields} = $r->{input_fields};
                                $r->{input_fields_idx} = {};
                                for my $j (0 .. $#{ $r->{input_fields} }) {
                                    $r->{input_fields_idx}{ $r->{input_fields}[$j] } = $j;
                                }

                                if ($on_input_header_row) {
                                    # log_trace "Calling on_input_header_row hook handler ...";
                                    $on_input_header_row->($r);
                                }

                                # reindex the fields, should the above hook
                                # handler adds/removes fields. let's save the
                                # old fields_idx to orig_fields_idx.
                                $r->{orig_input_fields_idx} = $r->{input_fields_idx};
                                $r->{input_fields_idx} = {};
                                for my $j (0 .. $#{ $r->{input_fields} }) {
                                    $r->{input_fields_idx}{ $r->{input_fields}[$j] } = $j;
                                }

                            } else {
                                # generate the hashref version of row if utility
                                # requires it
                                if ($r->{wants_input_row_as_hashref}) {
                                    $r->{input_row_as_hashref} = {};
                                    for my $j (0 .. $#{ $r->{input_row} }) {
                                        # ignore extraneous data fields
                                        last if $j >= @{ $r->{input_fields} };
                                        $r->{input_row_as_hashref}{ $r->{input_fields}[$j] } = $r->{input_row}[$j];
                                    }
                                }

                                if ($on_input_data_row) {
                                    # log_trace "Calling on_input_header_row hook handler ...";
                                    $on_input_data_row->($r);
                                }
                            }

                        } # while getline
                    } # for input_filename

                    # cleanup stash from csv-reading-related keys
                    delete $r->{input_filenames};
                    delete $r->{input_filenum};
                    delete $r->{input_filename};
                    delete $r->{input_fh};
                    delete $r->{input_rownum};
                    delete $r->{input_data_rownum};
                    delete $r->{input_row};
                    delete $r->{input_row_as_hashref};
                    delete $r->{input_fields};
                    delete $r->{input_fields_idx};
                    delete $r->{orig_input_fields_idx};
                    delete $r->{code_getline};
                    delete $r->{wants_input_row_as_hashref};
                } # READ_CSV

                if ($after_read_input) {
                    log_trace "Calling after_read_input handler ...";
                    $after_read_input->($r);
                }

                # cleanup stash from csv-outputting-related keys
                delete $r->{output_filenames};
                delete $r->{output_num_of_files};
                delete $r->{output_filenum};
                if ($r->{output_fh}) {
                    if ($r->{output_filename} ne '-') {
                        log_debug "Closing output file '$r->{output_filename}' ...";
                        close $r->{output_fh} or die [500, "Can't close output file '$r->{output_filename}': $!"];
                    }
                    delete $r->{output_fh};
                }
                delete $r->{output_filename};
                delete $r->{output_rownum};
                delete $r->{output_data_rownum};
                delete $r->{code_printline};
                delete $r->{has_printed_header};
                delete $r->{wants_switch_to_next_output_file};

                if ($on_end) {
                    log_trace "Calling on_end hook handler ...";
                    $on_end->($r);
                }

            }; # MAIN_EVAL

            my $err = $@;
            if ($err) {
                $err = [500, $err] unless ref $err;
                return $err;
            }

          RETURN_RESULT:
            if (!$r->{result}) {
                $r->{result} = [200];
            } elsif (!ref($r->{result})) {
                $r->{result} = [500, "BUG: Result (r->{result}) is set to a non-reference ($r->{result}), probably by one of the handlers"];
            } elsif (ref($r->{result}) ne 'ARRAY') {
                $r->{result} = [500, "BUG: Result (r->{result}) is not set to an enveloped result (arrayref) ($r->{result}), probably by one of the handlers"];
            }
            $r->{result};
        };
    } # CREATE_CODE

    my $meta;
  CREATE_META: {

        $meta = {
            v => 1.1,
            summary => $summary,
            description => $description,
            args => {},
            args_rels => {},
            links => $links,
            examples => $examples,
        };

      CREATE_ARGS_PROP: {
            if ($add_args) {
                $meta->{args}{$_} = $add_args->{$_} for keys %$add_args;
            }

            if ($accepts_csv) {
                $meta->{args}{$_} = {%{$argspecs_csv_input{$_}}} for keys %argspecs_csv_input;

                my $max_pos = -1;
                for (keys %{ $meta->{args} }) {
                    $max_pos = $meta->{args}{$_}{pos}
                        if defined $meta->{args}{$_}{pos} &&
                        $meta->{args}{$_}{pos} > $max_pos;
                }

                if ($accepts_multiple_csv) {
                    $meta->{args}{input_filenames} = {%{$argspecopt_input_filenames{input_filenames}}};
                    if (
                        # no other args use slurpy=1
                        !(grep {defined($meta->{args}{$_}{pos}) && $meta->{args}{$_}{pos} == 0 } keys %{$meta->{args}} )
                    ) {
                        my $max_pos = -1;
                        for (keys %{ $meta->{args} }) {
                            $max_pos = $meta->{args}{$_}{pos}
                                if defined $meta->{args}{$_}{pos} &&
                                $meta->{args}{$_}{pos} > $max_pos;
                        }
                        $meta->{args}{input_filenames}{pos} = $max_pos+1;
                        $meta->{args}{input_filenames}{slurpy} = 1;
                    }
                } else {
                    $meta->{args}{input_filename} = {%{$argspecopt_input_filename{input_filename}}};
                    if (
                        # no other args use pos=0
                        !(grep {defined($meta->{args}{$_}{pos}) && $meta->{args}{$_}{pos} == 0 } keys %{$meta->{args}} )
                    ) {
                        $meta->{args}{input_filename}{pos} = $max_pos+1;
                    }
                }
            } # if accepts_csv

            if ($outputs_csv) {
                $meta->{args}{$_} = {%{$argspecs_csv_output{$_}}} for keys %argspecs_csv_output;

                my $max_pos = -1;
                for (keys %{ $meta->{args} }) {
                    $max_pos = $meta->{args}{$_}{pos}
                        if defined $meta->{args}{$_}{pos} &&
                        $meta->{args}{$_}{pos} > $max_pos;
                }

                if ($outputs_multiple_csv) {
                    $meta->{args}{output_filenames} = {%{$argspecopt_output_filenames{output_filenames}}};
                    if (
                        # no other args use slurpy=1
                        !(grep {defined($meta->{args}{$_}{pos}) && $meta->{args}{$_}{pos} == 0 } keys %{$meta->{args}} )
                    ) {
                        $meta->{args}{output_filenames}{pos} = $max_pos+1;
                        $meta->{args}{output_filenames}{slurpy} = 1;
                    }
                } else {
                    $meta->{args}{output_filename} = {%{$argspecopt_output_filename{output_filename}}};
                    if (
                        # no other args use pos=0
                        !(grep {defined($meta->{args}{$_}{pos}) && $meta->{args}{$_}{pos} == 0 } keys %{$meta->{args}} )
                    ) {
                        $meta->{args}{output_filename}{pos} = $max_pos+1;
                    }
                }

                $meta->{args}{overwrite} = {%{$argspecopt_overwrite{overwrite}}};
            } # if outputs csv

        } # CREATE_ARGS_PROP

      CREATE_ARGS_RELS_PROP: {
            $meta->{args_rels} = {};
            if ($add_args_rels) {
                $meta->{args_rels}{$_} = $add_args_rels->{$_} for keys %$add_args_rels;
            }
        } # CREATE_ARGS_RELS_PROP

        if ($add_meta_props) {
            $meta->{$_} = $add_meta_props->{$_} for keys %$add_meta_props;
        }

    } # CREATE_META

    {
        my $package = caller();
        no strict 'refs';
        *{"$package\::$name"} = $code;
        #use DD; dd $meta;
        ${"$package\::SPEC"}{$name} = $meta;
    }

    1;
}

1;
# ABSTRACT: CLI utilities related to CSV

=for Pod::Coverage ^(csvutil)$

=head1 DESCRIPTION

This distribution contains the following CLI utilities:

# INSERT_EXECS_LIST


=head1 append:FUNCTIONS

=head2 compile_eval_code

Usage:

 $coderef = compile_eval_code($str, $label);

Compile string code C<$str> to coderef in 'main' package, without C<use strict>
or C<use warnings>. Die on compile error.


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

=head2 Other non-Perl-based CSV utilities

=head3 Python

B<csvkit>, L<https://csvkit.readthedocs.io/en/latest/>

=cut
