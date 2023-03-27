package App::CSVUtils::csv_unquote;

use 5.010001;
use strict;
use warnings;

# AUTHORITY
# DATE
# DIST
# VERSION

use App::CSVUtils::csv_csv;
use Perinci::Sub::Util qw(gen_modified_sub);

my $res = gen_modified_sub(
    output_name => 'csv_unquote',
    base_name => 'App::CSVUtils::csv_csv::csv_csv',
    summary => 'Make sure values of CSV are unquoted unless when necessary',
    description => <<'_',

This is a simple wrapper to <prog:csv-csv>. It's equivalent to:

    % csv-csv --no-output-always-quote --no-output-quote-empty ...

which is the default anyway.

_

    remove_args => [qw/output_always_quote output_quote_emty/],
    tags => ['category:munging', 'modifies-values'],

    modify_meta => sub {
        my $meta = shift;
        delete $meta->{args_rels};
        $meta->{examples} = [
            {
                summary => 'Make sure values of CSV are not quoted unless when necessary',
                argv => ['file.csv'],
                test => 0,
                'x.doc.show_result' => 0,
            },
        ];
        $meta->{links} = [
            {url=>'prog:csv-quote'},
        ];
    },
    output_code => sub {
        App::CSVUtils::csv_csv::csv_csv(
            @_,
            output_always_quote => 0,
            output_quote_empty => 0,
        );
    },
);
die "Can't generate sub: $res->[0] - $res->[1]" unless $res->[0] == 200;

1;
# ABSTRACT:
