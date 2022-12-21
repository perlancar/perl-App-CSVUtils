package App::CSVUtils::csv_shuf_rows;

use 5.010001;
use strict;
use warnings;

# AUTHORITY
# DATE
# DIST
# VERSION

use App::CSVUtils::csv_sort_rows;
use Perinci::Sub::Util qw(gen_modified_sub);

my $res = gen_modified_sub(
    output_name => 'csv_shuf_rows',
    base_name => 'App::CSVUtils::csv_sort_rows::csv_sort_rows',
    summary => 'Shuffle CSV rows',
    description => <<'_',

This is basically like Unix command `shuf` except it does not shuffle the header
row.

_

    remove_args => [qw/by_code by_fields by_sortsub sortsub_args key ci reverse hash/],
    modify_meta => sub {
        my $meta = shift;
        delete $meta->{args_rels};
        $meta->{examples} = [
            {
                summary => 'Shuffle a CSV file',
                argv => ['file.csv'],
                test => 0,
                'x.doc.show_result' => 0,
            },
        ];
    },
    output_code => sub {
        App::CSVUtils::csv_sort_rows::csv_sort_rows(
            @_,
            # TODO: this feels less shuffled
            by_code => sub { int(rand 3)-1 }, # return -1,0,1 randomly
        );
    },
);
die "Can't generate sub: $res->[0] - $res->[1]" unless $res->[0] == 200;

1;
# ABSTRACT:
