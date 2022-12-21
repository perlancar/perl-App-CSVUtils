package App::CSVUtils::csv_fill_template;

use 5.010001;
use strict;
use warnings;

# AUTHORITY
# DATE
# DIST
# VERSION

use App::CSVUtils qw(gen_csv_util);

gen_csv_util(
    name => 'csv_fill_template',
    summary => 'Substitute template values in a text file with fields from CSV rows',
    description => <<'_',

Templates are text that contain `[[NAME]]` field placeholders. The field
placeholders will be replaced by values from the CSV file. This is a simple
alternative to mail-merge. (I first wrote this utility because LibreOffice
Writer, as always, has all the annoying bugs; that particular time, one that
prevented mail merge from working.)

Example:

    % cat madlib.txt
    Today I went to the park. I saw a(n) [[adjective1]] [[noun1]] running
    towards me. It looked hungry, really hungry. Horrified and terrified, I took
    a(n) [[adjective2]] [[noun2]] and waved the thing [[adverb1]] towards it.
    [[adverb2]], when it arrived at my feet, it [[verb1]] and [[verb2]] me
    instead. I was relieved, the [[noun1]] was a friendly creature after all.
    After we [[verb3]] for a little while, I went home with a(n) [[noun3]] on my
    face. That was an unforgettable day indeed.

    % cat values.csv
    adjective1,adjective2,adjective3,noun1,noun2,noun3,verb1,verb2,verb3,adverb1,adverb2
    slow,gigantic,sticky,smartphone,six-wheeler truck,lollipop,piece of tissue,threw,kissed,stared,angrily,hesitantly
    sweet,delicious,red,pelican,bottle of parfume,desk,exercised,jumped,slept,confidently,passively

    % csv-fill-template values.csv madlib.txt
    Today I went to the park. I saw a(n) slow six-wheeler truck running
    towards me. It looked hungry, really hungry. Horrified and terrified, I took
    a(n) gigantic lollipop and waved the thing angrily towards it.
    hesitantly, when it arrived at my feet, it threw and kissed me
    instead. I was relieved, the six-wheeler truck was a friendly creature after all.
    After we stared for a little while, I went home with a(n) piece of tissue on my
    face. That was an unforgettable day indeed.

    ---
    Today I went to the park. I saw a(n) sweet pelican running
    towards me. It looked hungry, really hungry. Horrified and terrified, I took
    a(n) delicious bottle of parfume and waved the thing confidently towards it.
    passively, when it arrived at my feet, it exercised and jumped me
    instead. I was relieved, the pelican was a friendly creature after all.
    After we slept for a little while, I went home with a(n) desk on my
    face. That was an unforgettable day indeed.

_

    add_args => {
        template_filename => {
            schema => 'filename*',
            req => 1,
            pos => 1,
        },
    },

    examples => [
    ],

    writes_csv => 0,

    on_begin => sub {
        my $r = shift;
        $r->{wants_input_row_as_hashref}++;

        require File::Slurper::Dash;

        my $template = File::Slurper::Dash::read_text($r->{util_args}{template_filename});

        # this is the key we add to the stash
        $r->{template} = $template;
        $r->{filled_template} = '';
    },

    on_input_data_row => sub {
        my $r = shift;

        my $text = $r->{template};
        $text =~ s/\[\[(.+?)\]\]/defined $r->{input_row_as_hashref}{$1} ? $r->{input_row_as_hashref}{$1} : "[[UNDEFINED:$1]]"/eg;
        $r->{filled_templates} .= (length $r->{filled_template} ? "\n---\n" : "") . $text;
    },

    writes_csv => 0,

    on_end => sub {
        my $r = shift;
        $r->{result} = [200, "OK", $r->{filled_templates}];
    },
);

1;
# ABSTRACT:
