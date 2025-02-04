package App::CSVUtils::csv_setop;

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
    name => 'csv_setop',
    summary => 'Set operation (union/unique concatenation of rows, intersection/common rows, difference of rows) against several CSV files',
    description => <<'MARKDOWN',

This utility lets you perform one of several set options against several CSV
files:
- union
- intersection
- difference
- symmetric difference

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

You can specify `--compare-fields` to consider some fields only, for example
`--union --compare-fields a,b file1.csv file2.csv`:

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

Finally you can print out only certain fields using `--result-fields`.

MARKDOWN
    add_args => {
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

    reads_multiple_csv => 1,

    tags => ['category:combining', 'set'],

    on_begin => sub {
        my $r = shift;

        # check arguments
        die [400, "Please specify at least 2 files"]
            unless @{ $r->{util_args}{input_filenames} } >= 2;

        # these are the keys we add to the stash
        $r->{all_input_data_rows} = [];  # array of all data rows, one elem for each input file
        $r->{all_input_fields} = [];     # array of input_fields, one elem for each input file
        $r->{all_input_fields_idx} = []; # array of input_fields_idx, one elem for each input file
    },

    on_input_header_row => sub {
        my $r = shift;

        $r->{all_input_fields}    [ $r->{input_filenum}-1 ] = $r->{input_fields};
        $r->{all_input_fields_idx}[ $r->{input_filenum}-1 ] = $r->{input_fields_idx};
        $r->{all_input_data_rows} [ $r->{input_filenum}-1 ] = [];
    },

    on_input_data_row => sub {
        my $r = shift;

        push @{ $r->{all_input_data_rows}[ $r->{input_filenum}-1 ] },
            $r->{input_row};
    },

    after_close_input_files => sub {
        require Tie::IxHash;

        my $r = shift;

        my $op = $r->{util_args}{op};
        my $ci = $r->{util_args}{ignore_case};
        my $num_files = @{ $r->{util_args}{input_filenames} };

        my @compare_fields; # elem = [fieldname-for-file1, fieldname-for-file2, ...]
        if (defined $r->{util_args}{compare_fields}) {
            my @ff = ref($r->{util_args}{compare_fields}) eq 'ARRAY' ?
                @{$r->{util_args}{compare_fields}} : split(/,/, $r->{util_args}{compare_fields});
            for my $field_idx (0..$#ff) {
                my @ff2 = split /:/, $ff[$field_idx];
                for (@ff2+1 .. $num_files) {
                    push @ff2, $ff2[0];
                }
                $compare_fields[$field_idx] = \@ff2;
            }
            # XXX check that specified fields exist
        } else {
            for my $field_idx (0..$#{ $r->{all_input_fields}[0] }) {
                $compare_fields[$field_idx] = [
                    map { $r->{all_input_fields}[0][$field_idx] } 0..$num_files-1];
            }
        }

        my @result_fields; # elem = fieldname, ...
        if (defined $r->{util_args}{result_fields}) {
            @result_fields = ref($r->{util_args}{result_fields}) eq 'ARRAY' ?
                @{$r->{util_args}{result_fields}} : split(/,/, $r->{util_args}{result_fields});
            # XXX check that specified fields exist
        } else {
            @result_fields = @{ $r->{all_input_fields}[0] };
        }
        $r->{output_fields} = \@result_fields;

        tie my(%res), 'Tie::IxHash';

        my $code_get_compare_key = sub {
            my ($file_idx, $row_idx) = @_;
            my $row   = $r->{all_input_data_rows}[$file_idx][$row_idx];
            my $key = join "|", map {
                my $field = $compare_fields[$_][$file_idx];
                my $field_idx = $r->{all_input_fields_idx}[$file_idx]{$field};
                my $val = defined $field_idx ? $row->[$field_idx] : "";
                $val = uc $val if $ci;
                $val;
            } 0..$#compare_fields;
            #say "D:compare_key($file_idx, $row_idx)=<$key>";
            $key;
        };

        my $code_print_result_row = sub {
            my ($file_idx, $row) = @_;
            my @res_row = map {
                my $field = $result_fields[$_];
                my $field_idx = $r->{all_input_fields_idx}[$file_idx]{$field};
                defined $field_idx ? $row->[$field_idx] : "";
            } 0..$#result_fields;
            $r->{code_print_row}->(\@res_row);
        };

        if ($op eq 'intersect') {
            for my $file_idx (0..$num_files-1) {
                if ($file_idx == 0) {
                    for my $row_idx (0..$#{ $r->{all_input_data_rows}[$file_idx] }) {
                        my $key = $code_get_compare_key->($file_idx, $row_idx);
                        $res{$key} //= [1, $row_idx]; # [num_of_occurrence, row_idx]
                    }
                } else {
                    for my $row_idx (0..$#{ $r->{all_input_data_rows}[$file_idx] }) {
                        my $key = $code_get_compare_key->($file_idx, $row_idx);
                        if ($res{$key} && $res{$key}[0] == $file_idx) {
                            $res{$key}[0]++;
                        }
                    }
                }

                # print result
                if ($file_idx == $num_files-1) {
                    for my $key (keys %res) {
                        $code_print_result_row->(
                            0, $r->{all_input_data_rows}[0][$res{$key}[1]])
                            if $res{$key}[0] == $num_files;
                    }
                }
            } # for file_idx

        } elsif ($op eq 'union') {

            for my $file_idx (0..$num_files-1) {
                for my $row_idx (0..$#{ $r->{all_input_data_rows}[$file_idx] }) {
                    my $key = $code_get_compare_key->($file_idx, $row_idx);
                    next if $res{$key}++;
                    my $row = $r->{all_input_data_rows}[$file_idx][$row_idx];
                    $code_print_result_row->($file_idx, $row);
                }
            } # for file_idx

        } elsif ($op eq 'diff') {

            for my $file_idx (0..$num_files-1) {
                if ($file_idx == 0) {
                    for my $row_idx (0..$#{ $r->{all_input_data_rows}[$file_idx] }) {
                        my $key = $code_get_compare_key->($file_idx, $row_idx);
                        $res{$key} //= [$file_idx, $row_idx];
                    }
                } else {
                    for my $row_idx (0..$#{ $r->{all_input_data_rows}[$file_idx] }) {
                        my $key = $code_get_compare_key->($file_idx, $row_idx);
                        delete $res{$key};
                    }
                }

                # print result
                if ($file_idx == $num_files-1) {
                    for my $key (keys %res) {
                        my ($file_idx, $row_idx) = @{ $res{$key} };
                        $code_print_result_row->(
                            0, $r->{all_input_data_rows}[$file_idx][$row_idx]);
                    }
                }
            } # for file_idx

        } elsif ($op eq 'symdiff') {

            for my $file_idx (0..$num_files-1) {
                if ($file_idx == 0) {
                    for my $row_idx (0..$#{ $r->{all_input_data_rows}[$file_idx] }) {
                        my $key = $code_get_compare_key->($file_idx, $row_idx);
                        $res{$key} //= [1, $file_idx, $row_idx];  # [num_of_occurrence, file_idx, row_idx]
                    }
                } else {
                    for my $row_idx (0..$#{ $r->{all_input_data_rows}[$file_idx] }) {
                        my $key = $code_get_compare_key->($file_idx, $row_idx);
                        if (!$res{$key}) {
                            $res{$key} = [1, $file_idx, $row_idx];
                        } else {
                            $res{$key}[0]++;
                        }
                    }
                }

                # print result
                if ($file_idx == $num_files-1) {
                    for my $key (keys %res) {
                        my ($num_occur, $file_idx, $row_idx) = @{ $res{$key} };
                        $code_print_result_row->(
                            0, $r->{all_input_data_rows}[$file_idx][$row_idx])
                            if $num_occur == 1;
                    }
                }
            } # for file_idx

        } else {

            die [400, "Unknown/unimplemented op '$op'"];

        }

        #use DD; dd +{
        #    compare_fields => \@compare_fields,
        #    result_fields => \@result_fields,
        #    all_input_data_rows=>$r->{all_input_data_rows},
        #    all_input_fields=>$r->{all_input_fields},
        #    all_input_fields_idx=>$r->{all_input_fields_idx},
        #};
    },
);

1;
# ABSTRACT:
