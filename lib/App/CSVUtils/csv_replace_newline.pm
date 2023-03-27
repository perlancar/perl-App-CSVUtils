package App::CSVUtils::csv_replace_newline;

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
    name => 'csv_replace_newline',
    summary => 'Replace newlines in CSV values',
    description => <<'_',

Some CSV parsers or applications cannot handle multiline CSV values. This
utility can be used to convert the newline to something else. There are a few
choices: replace newline with space (`--with-space`, the default), remove
newline (`--with-nothing`), replace with encoded representation
(`--with-backslash-n`), or with characters of your choice (`--with 'blah'`).

_
    add_args => {
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
    tags => ['category:munging', 'modifies-rows'],

    examples => [
        {
            summary => 'Replace newline in a CSV file to space',
            argv => ['file.csv'],
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],

    on_input_header_row => sub {
        my $r = shift;

        $r->{output_fields} = [];
        my $with = $r->{util_args}{with};
        for my $j (0 .. $#{ $r->{input_fields} }) {
            my $val = $r->{input_fields}[$j];
            $val =~ s/[\015\012]+/$with/g;
            push @{ $r->{output_fields} }, $val;
        }
    },

    on_input_data_row => sub {
        my $r = shift;

        my $row = [];
        my $with = $r->{util_args}{with};
        for my $j (0 .. $#{ $r->{input_fields} }) {
            my $val = $r->{input_row}[$j];
            $val =~ s/[\015\012]+/$with/g;
            push @$row, $val;
        }

        $r->{code_print_row}->($row);
    },
);

1;
# ABSTRACT:
