package App::CSVUtils::csv_add_fields;

use 5.010001;
use strict;
use warnings;

# AUTHORITY
# DATE
# DIST
# VERSION

use App::CSVUtils qw(
                        gen_csv_util
                        compile_eval_code
                        eval_code
                );

gen_csv_util(
    name => 'csv_add_fields',
    summary => 'Add one or more fields to CSV file',
    description => <<'MARKDOWN',

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
first data row). `$csv` is the <pm:Text::CSV_XS> object. `$main::fields_idx` is
also available for additional information.

If `-e` is not supplied, the new fields will be getting the default value of
empty string (`''`).

MARKDOWN
    add_args => {
        %App::CSVUtils::argspec_fields_1plus_nocomp,
        %App::CSVUtils::argspecopt_eval,
        %App::CSVUtils::argspecopt_hash,
        after => {
            summary => 'Put the new field(s) after specified field',
            schema => 'str*',
            completion => \&_complete_field,
        },
        before => {
            summary => 'Put the new field(s) before specified field',
            schema => 'str*',
            completion => \&_complete_field,
        },
        at => {
            summary => 'Put the new field(s) at specific position '.
                '(1 means at the front of all others)',
            schema => 'posint*',
        },
    },
    add_args_rels => {
        choose_one => [qw/after before at/],
    },
    tags => ['category:munging','adds-fields'],

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

    on_begin => sub {
        my $r = shift;

        # check arguments
        if (!defined($r->{util_args}{fields}) || !@{ $r->{util_args}{fields} }) {
            die [400, "Please specify one or more fields (-f)"];
        }
    },

    on_input_header_row => sub {
        my $r = shift;

        # check that the new fields are not duplicate (against existing fields
        # and against itself)
        my %seen;
        for (@{ $r->{util_args}{fields} }) {
            unless (length $_) {
                die [400, "New field name cannot be empty"];
            }
            if (defined $r->{input_fields_idx}{$_}) {
                die [412, "Field '$_' already exists"];
            }
            if ($seen{$_}++) {
                die [412, "Duplicate new field '$_'"];
            }
        }

        # determine the position at which to insert the new fields
        my $new_fields_idx;
        if (defined $r->{util_args}{at}) {
            $new_fields_idx = $r->{util_args}{at}-1;
        } elsif (defined $r->{util_args}{before}) {
            for (0..$#{ $r->{input_fields} }) {
                if ($r->{input_fields}[$_] eq $r->{util_args}{before}) {
                    $new_fields_idx = $_;
                    last;
                }
            }
            die [400, "Field '$r->{util_args}{before}' (to add new fields before) not found"]
                unless defined $new_fields_idx;
        } elsif (defined $r->{util_args}{after}) {
            for (0..$#{ $r->{input_fields} }) {
                if ($r->{input_fields}[$_] eq $r->{util_args}{after}) {
                    $new_fields_idx = $_+1;
                    last;
                }
            }
            die [400, "Field '$r->{util_args}{after}' (to add new fields after) not found"]
                unless defined $new_fields_idx;
        } else {
            $new_fields_idx = @{ $r->{input_fields} };
        }

        # for printing the header
        $r->{output_fields} = [@{ $r->{input_fields} }];
        splice @{ $r->{output_fields} }, $new_fields_idx, 0, @{ $r->{util_args}{fields} };

        $r->{wants_input_row_as_hashref} = 1 if $r->{util_args}{hash};

        # we add the following keys to the stash
        $r->{code} = compile_eval_code($r->{util_args}{eval} // 'return', 'eval');
        $r->{new_fields_idx} = $new_fields_idx;
    },

    on_input_data_row => sub {
        my $r = shift;

        my @vals;
        eval { @vals = eval_code($r->{code}, $r, $r->{wants_input_row_as_hashref} ? $r->{input_row_as_hashref} : $r->{input_row}) };
        die [500, "Error while adding field(s) '".join(",", @{$r->{util_args}{fields}})."' for row #$r->{input_rownum}: $@"]
            if $@;
        if (ref $vals[0] eq 'ARRAY') { @vals = @{ $vals[0] } }
        splice @{ $r->{input_row} }, $r->{new_fields_idx}, 0,
            (map { $_ // '' } @vals[0 .. $#{$r->{util_args}{fields}}]);
        $r->{code_print_row}->($r->{input_row});
    },
);

1;
# ABSTRACT:
