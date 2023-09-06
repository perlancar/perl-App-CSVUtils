package App::CSVUtils::csv_sort_fields_by_spec;

use 5.010001;
use strict;
use warnings;

# AUTHORITY
# DATE
# DIST
# VERSION

use App::CSVUtils;
use App::CSVUtils::csv_sort_fields;
use Perinci::Sub::Util qw(gen_modified_sub);

my $res = gen_modified_sub(
    output_name => 'csv_sort_fields_by_spec',
    base_name => 'App::CSVUtils::csv_sort_fields::csv_sort_fields',
    summary => 'Sort CSV fields by spec',
    description => <<'MARKDOWN',

This is a thin wrapper for <prog:csv-sort-fields> to allow you to sort "by
spec". Sorting by spec is an advanced form of sorting by example. In addition to
specifying strings of examples, you can also specify regexes or Perl sorter
codes. For more details, see the sorting backend module <pm:Sort::BySpec>.

To specify a regex on the command-line, use one of these forms:

    /.../
    qr(...)

and to specify Perl code on the command-line, use this form:

    sub { ... }

For example, modifying from example in `Sort::BySpec`'s Synopsis, you want to
sort these fields:

    field1..field15 field42

as follow: 1) put fields with odd numbers first in ascending order; 2) put the
specific fields field4, field2, field42 in that order; 3) put the remaining
fields of even numbers in descending order. To do this:

    % perl -E'say join(",",map {"field$_"} 1..15,42)' | csv-sort-fields-by-spec - \
        'qr([13579]\z)' 'sub { my($a,$b)=@_; for($a,$b){s/field//} $a<=>$b }' \
        field4 field2 field42 \
        'sub { my($a,$b)=@_; for($a,$b){s/field//} $b<=>$a }'

The result:

    field1,field3,field5,field7,field9,field11,field13,field15,field4,field2,field42,field14,field12,field10,field8,field6

MARKDOWN
    remove_args => ['by_examples', 'by_code', 'by_sortsub'],
    add_args => {
        specs => {
            'x.name.is_plural' => 1,
            'x.name.singular' => 'spec',
            summary => 'Spec entries',
            'summary.alt.plurality.singular' => 'Add a spec entry',
            schema => ['array*', of=>'str_or_re_or_code*'],
            req => 1,
            pos => 1,
            slurpy => 1,
            completion => \&App::CSVUtils::_complete_field,
        },
    },
    modify_args => {
        output_filename => sub {
            my $argspec = shift;
            delete $argspec->{pos};
        },
    },
    tags => ['category:sorting'],
    output_code => sub {
        my %args = @_;
        my $spec = delete $args{specs};
        require Sort::BySpec;
        App::CSVUtils::csv_sort_fields::csv_sort_fields(
            %args,
            by_code => Sort::BySpec::cmp_by_spec(spec=>$spec),
        );
    },
);

1;
# ABSTRACT:

=for Pod::Coverage ^(on|after|before)_.+$
