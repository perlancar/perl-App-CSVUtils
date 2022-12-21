package App::CSVUtils::csv_select_rows;

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
                );

gen_csv_util(
    name => 'csv_select_rows',
    summary => 'Only output of specified row numbers',
    description => <<'_',

To select rows by Perl code, see <prog:csv-grep>.

_
    add_args => {
        rownum_spec => {
            schema => 'str*',
            summary => 'Row number (e.g. 1 for first data row), '.
                'range (3-7), or comma-separated list of such (3-7,10,20-23)',
            req => 1,
            pos => 1,
        },
    },
    examples => [
        {
            summary => 'Only show rows 1-3 (first to third data rows)',
            argv => ['file.csv', '1-3'],
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],
    links => [
        {url=>'prog:csvgrep'},
    ],

    on_input_header_row => sub {
        my $r = shift;

        my $spec = $r->{util_args}{rownum_spec};
        my @codestr;
        for my $spec_item (split /\s*,\s*/, $spec) {
            if ($spec_item =~ /\A\d+\z/) {
                push @codestr, "(\$main::i == $spec_item)";
            } elsif ($spec_item =~ /\A(\d+)\s*-\s*(\d+)\z/) {
                push @codestr, "(\$main::i >= $1 && \$main::i <= $2)";
            } else {
                die [400, "Invalid rownum specification '$spec_item'"];
            }
        }

        # we add the following keys to the stash
        $r->{code} = compile_eval_code(join(" || ", @codestr), 'from rownum_spec');
    },

    on_input_data_row => sub {
        my $r = shift;

        local $main::i = $r->{input_data_rownum};
        $r->{code_print_row}->($r->{input_row}) if $r->{code}->();
    },
);

1;
# ABSTRACT:
