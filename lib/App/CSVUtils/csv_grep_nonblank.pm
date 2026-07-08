package App::CSVUtils::csv_grep_nonblank;

use 5.010001;
use strict;
use warnings;

# AUTHORITY
# DATE
# DIST
# VERSION

use App::CSVUtils::csv_grep;
use Perinci::Sub::Util qw(gen_modified_sub);

my $res = gen_modified_sub(
    output_name => 'csv_grep_nonblank',
    base_name => 'App::CSVUtils::csv_grep::csv_grep',
    summary => 'Remove blank CSV files',
    description => <<'MARKDOWN',

This is a simple wrapper to <prog:csv-grep>. It's equivalent to:

    % csv-grep -e 'join("", @$_) ne ""' ...

Keywords: non-blanks, remove blank lines

MARKDOWN

    remove_args => [qw/eval hash/],
    tags => ['category:filtering'],

    modify_meta => sub {
        my $meta = shift;
        $meta->{examples} = [
            {
                summary => 'Make sure there are no blank CSV lines',
                argv => ['file.csv'],
                test => 0,
                'x.doc.show_result' => 0,
            },
        ];
        $meta->{links} = [
            {url=>'prog:csv-grep'},
        ];
    },
    output_code => sub {
        App::CSVUtils::csv_grep::csv_grep(
            @_,
            eval => 'join("", @$_) ne ""',
        );
    },
);
die "Can't generate sub: $res->[0] - $res->[1]" unless $res->[0] == 200;

1;
# ABSTRACT:
