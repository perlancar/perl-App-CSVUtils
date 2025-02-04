package App::CSVUtils::csv_cmp;

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
                );

gen_csv_util(
    name => 'csv_cmp',
    summary => 'Compare two CSV files value by value',
    description => <<'MARKDOWN',

This utility is modelled after the Unix command `cmp`; it compares two CSV files
value by value and ignore quoting (and can be instructed to ignore whitespaces,
case difference).

If all the values of two CSV files are identical, then utility will exit with
code 0. If a value differ, this utility will stop, print the difference and exit
with code 1.

If `-l` (`--detail`) option is specified, all differences will be reported. Note
that in `cmp` Unix command, the `-l` option is called `--verbose`. The detailed
report is in the form of CSV:

    rownum,fieldnum,value1,value2

where `rownum` begins at 1 (for header row), `fieldnum` begins at 1 (first
field), `value1` is the value in first CSV file, `value2` is the value in the
second CSV file.

Other notes:

* If none of the field selection options are used, it means all fields are
  included (equivalent to `--include-all-fields`).

* Field selection will be performed on the first CSV file, then the indexes will
be used for the second CSV file.

MARKDOWN
    add_args => {
        %App::CSVUtils::argspecsopt_field_selection,
        %App::CSVUtils::argspecsopt_show_selected_fields,

        detail => {
            summary => 'Report all differences instead of just the first one',
            schema => 'true*',
            cmdline_aliases => {l=>{}},
        },
        quiet => {
            summary => 'Do not report, just signal via exit code',
            schema => 'true*',
            cmdline_aliases => {q=>{}},
        },
        ignore_case => {
            summary => 'Ignore case difference',
            schema => 'bool*',
            cmdline_aliases => {i=>{}},
        },
        ignore_leading_ws => {
            summary => 'Ignore leading whitespaces',
            schema => 'bool*',
        },
        ignore_trailing_ws => {
            summary => 'Ignore trailing whitespaces',
            schema => 'bool*',
        },
        ignore_ws => {
            summary => 'Ignore leading & trailing whitespaces',
            schema => 'bool*',
        },
    },
    tags => [
        'accepts-regex', # for selecting fields
        'category:comparing',
    ],

    examples => [
        {
            summary => 'Compare two identical files, will output nothing and exits 0',
            argv => ['file.csv', 'file.csv'],
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'Compare two CSV files case-insensitively (-i), show detailed report (-l)',
            argv => ['file1.csv', 'file2.csv', '-il'],
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],

    reads_multiple_csv => 1,

    on_begin => sub {
        my $r = shift;

        unless ($r->{util_args}{input_filenames} && @{ $r->{util_args}{input_filenames} } == 2) {
            die [400, "Please specify exactly two files to compare"];
        }
        # no point in generating detailed report if we're not going to show it
        $r->{util_args}{detail} = 0 if $r->{util_args}{quiet};
    },

    before_open_input_files => sub {
        my $r = shift;

        # we add the following keys to the stash
        $r->{all_input_rows} = [[], []]; # including header row. format: [ [row1 of csv1, row2 of csv1...], [row1 of csv2, row2 of csv2, ...] ]
        $r->{selected_fields_idx_array_sorted} = undef;
    },

    on_input_header_row => sub {
        my $r = shift;

        push @{ $r->{all_input_rows}[ $r->{input_filenum}-1 ] }, $r->{input_fields};

        if ($r->{input_filenum} == 1) {
            # set selected_fields_idx_array_sorted
            my $res = App::CSVUtils::_select_fields($r->{input_fields}, $r->{input_fields_idx}, $r->{util_args}, 'all');
            die $res unless $res->[0] == 100;
            my $selected_fields = $res->[2][0];
            my $selected_fields_idx_array = $res->[2][1];
            die [412, "At least one field must be selected"]
                unless @$selected_fields;
            $r->{selected_fields_idx_array_sorted} = [sort { $b <=> $a } @$selected_fields_idx_array];

            if ($r->{util_args}{show_selected_fields}) {
                $r->{wants_skip_files}++;
                $r->{result} = [200, "OK", $selected_fields];
                return;
            }
        }
    },

    on_input_data_row => sub {
        my $r = shift;

        push @{ $r->{all_input_rows}[ $r->{input_filenum}-1 ] }, $r->{input_row};
    },

    after_close_input_files => sub {
        my $r = shift;

        $r->{output_fields} = ["rownum","fieldnum","value1","value2"];

        my $exit_code = 0;
        my $numrows1   = @{ $r->{all_input_rows}[0] };
        my $numrows2   = @{ $r->{all_input_rows}[1] };
        my $numfields1 = @{ $r->{all_input_rows}[0][0] };
        my $numfields2 = @{ $r->{all_input_rows}[1][0] };

        if ($numfields1 > $numfields2) {
            warn "csv-cmp: second CSV only has $numfields2 field(s) (vs $numfields1)\n"
                unless $r->{util_args}{quiet};
            $exit_code = 1;
            goto DONE unless $r->{util_args}{detail};
        } elsif ($numfields1 < $numfields2) {
            warn "csv-cmp: first CSV only has $numfields1 field(s) (vs $numfields2)\n"
                unless $r->{util_args}{quiet};
            $exit_code = 1;
            goto DONE unless $r->{util_args}{detail};
        }

        my $numrows_min = $numrows1 < $numrows2 ? $numrows1 : $numrows2;
        for my $rownum (1 .. $numrows_min) {
            for my $j (@{ $r->{selected_fields_idx_array_sorted} }) {
                my $fieldnum = $j+1;
                my $origvalue1 = my $value1 = $r->{all_input_rows}[0][ $rownum-1 ][ $fieldnum-1 ];
                my $origvalue2 = my $value2 = $r->{all_input_rows}[1][ $rownum-1 ][ $fieldnum-1 ];

                if ($r->{util_args}{ignore_case}) {
                    $value1 = lc $value1;
                    $value2 = lc $value2;
                }
                if ($r->{util_args}{ignore_ws} || $r->{util_args}{ignore_leading_ws}) {
                    $value1 =~ s/\A\s+//s;
                    $value2 =~ s/\A\s+//s;
                }
                if ($r->{util_args}{ignore_ws} || $r->{util_args}{ignore_trailing_ws}) {
                    $value1 =~ s/\s+\z//s;
                    $value2 =~ s/\s+\z//s;
                }

                if ($value1 ne $value2) {
                    $exit_code = 1;
                    if ($r->{util_args}{detail}) {
                        $r->{code_print_row}->([$rownum, $fieldnum, $origvalue1, $origvalue2])
                            unless $r->{util_args}{quiet};
                    } else {
                        warn "csv-cmp: Value differ at rownum $rownum fieldnum $fieldnum: '$origvalue1' vs '$origvalue2'\n"
                            unless $r->{util_args}{quiet};
                        goto DONE;
                    }
                }
            } # for field
        } # for row

        if ($numrows1 > $numrows2) {
            warn "csv-cmp: EOF: second CSV only has $numrows2 row(s) (vs $numrows1)\n"
                unless $r->{util_args}{quiet};
            $exit_code = 1;
            goto DONE unless $r->{util_args}{detail};
        } elsif ($numrows1 < $numrows2) {
            warn "csv-cmp: EOF: first CSV only has $numrows1 row(s) (vs $numrows2)\n"
                unless $r->{util_args}{quiet};
            $exit_code = 1;
            goto DONE unless $r->{util_args}{detail};
        }

      DONE:
        $r->{result} = [200, "OK", "", {"cmdline.exit_code"=>$exit_code}];
    },
);

1;
# ABSTRACT:
