package App::CSVUtils::csv_uniq;

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
    name => 'csv_uniq',
    summary => 'Report or omit duplicated values in CSV',
    add_args => {
        %App::CSVUtils::argspec_fields_1plus,
        ignore_case => {
            summary => 'Ignore case when comparing',
            schema => 'true*',
            cmdline_aliases => {i=>{}},
        },
        unique => {
            summary => 'Instead of reporting duplicate values, report unique values instead',
            schema => 'true*',
        },
    },
    examples => [
        {
            summary => 'Check that field "foo" in CSV is unique, compare case-insensitively, report duplicates',
            argv => ['file.csv', '-i', 'foo'],
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'Check that combination of fields "foo", "bar", "baz" in CSV is unique, report duplicates',
            argv => ['file.csv', 'foo', 'bar', 'baz'],
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],

    writes_csv => 0,

    on_input_header_row => sub {
        my $r = shift;

        # we add this key to the stash
        $r->{seen} = {};

        # check arguments
        for my $field (@{ $r->{util_args}{fields} }) {
            die [404, "Unknown field '$field'"] unless defined $r->{input_fields_idx}{$field};
        }
    },

    on_input_data_row => sub {
        my $r = shift;

        my @vals;
        for my $field (@{ $r->{util_args}{fields} }) {
            my $fieldval = $r->{input_row}[ $r->{input_fields_idx}{$field} ] // '';
            push @vals, $r->{util_args}{ignore_case} ? lc($fieldval) : $fieldval;
        }
        my $val = join("|", @vals);
        $r->{seen}{$val}++;
        unless ($r->{util_args}{unique}) {
            print "csv-uniq: Duplicate value '$val'\n" if $r->{seen}{$val} == 2;
        }
    },

    on_end => sub {
        my $r = shift;

        if ($r->{util_args}{unique}) {
            for my $val (sort keys %{ $r->{seen} }) {
                print "csv-uniq: Unique value '$val'\n" if $r->{seen}{$val} == 1;
            }
        }
    },
);

1;
# ABSTRACT:
