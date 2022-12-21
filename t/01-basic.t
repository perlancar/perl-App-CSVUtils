#!perl

use 5.010001;
use strict;
use warnings;
use Test::Exception;
use Test::More 0.98;
use Test::Needs;

use App::CSVUtils;
use Capture::Tiny ':all';
use File::Temp qw(tempdir);
use File::Slurper qw(write_text);

my $dir = tempdir(CLEANUP => 1);
write_text("$dir/empty.csv", '');
write_text("$dir/1.csv", "f1,f2,f3\n1,2,3\n4,5,6\n7,8,9\n");
write_text("$dir/2.csv", "f1\n1\n2\n3\n");
write_text("$dir/3.csv", qq(f1,f2\n1,"row\n1"\n2,"row\n2"\n));
write_text("$dir/4.csv", qq(f1,F3,f2\n1,2,3\n4,5,6\n));
write_text("$dir/5.csv", qq(f1\n1\n2\n3\n4\n5\n6\n));
write_text("$dir/no-rows.csv", qq(f1,f2,f3\n));
write_text("$dir/no-header-1.csv", "1,2,3\n4,5,6\n7,8,9\n");

write_text("$dir/1.tsv", "f1\tf2\tf3\n1\t2\t3\n4\t5\t6\n7\t8\t9\n");

write_text("$dir/sep_char-semicolon.csv", "f1;f2\n1;2\n3;4\n");

write_text("$dir/sort-rows.csv", qq(f1,f2\n2,andy\n1,Andy\n10,Chuck\n));
write_text("$dir/sort-fields.csv", qq(four,two,eighteen\n4,2,18));

subtest "common option: input_sep_char" => sub {
    my $res;

    require App::CSVUtils::csv_dump;
    $res = App::CSVUtils::csv_dump::csv_dump(input_filename=>"$dir/sep_char-semicolon.csv", input_sep_char=>";");
    is_deeply($res, [200,"OK",[["f1","f2"],[1,2],[3,4]]])
        or diag explain $res;
};

subtest csv_add_fields => sub {
    my ($res, $stdout);

    require App::CSVUtils::csv_add_fields;

    $res = App::CSVUtils::csv_add_fields::csv_add_fields(input_filename=>"$dir/1.csv", fields=>["f4"], eval=>"blah +");
    is($res->[0], 400, "error in eval code -> dies") or diag explain $res;

    $res = App::CSVUtils::csv_add_fields::csv_add_fields(input_filename=>"$dir/1.csv", fields=>["f3"], eval=>"1");
    is($res->[0], 412, "adding existing field -> error") or diag explain $res;

    $res = App::CSVUtils::csv_add_fields::csv_add_fields(input_filename=>"$dir/1.csv", fields=>[""], eval=>"1");
    is($res->[0], 400, "empty field -> error") or diag explain $res;

    $res = App::CSVUtils::csv_add_fields::csv_add_fields(input_filename=>"$dir/1.csv", fields=>["f4","f5","f4"], eval=>"1");
    is($res->[0], 412, "duplicate in fields -> error") or diag explain $res;

    $stdout = capture_stdout { $res = App::CSVUtils::csv_add_fields::csv_add_fields(input_filename=>"$dir/1.csv", fields=>["f4"]) };
    is($stdout, "f1,f2,f3,f4\n1,2,3,\n4,5,6,\n7,8,9,\n", "output (with no eval)");
    $stdout = capture_stdout { $res = App::CSVUtils::csv_add_fields::csv_add_fields(input_filename=>"$dir/1.csv", fields=>["f4"], eval=>'$main::rownum*2') };
    is($stdout, "f1,f2,f3,f4\n1,2,3,4\n4,5,6,6\n7,8,9,8\n", "output (with eval)");
    $stdout = capture_stdout { $res = App::CSVUtils::csv_add_fields::csv_add_fields(input_filename=>"$dir/1.csv", fields=>["f4","f6","f5"], eval=>'[11,13,12]') };
    is($stdout, "f1,f2,f3,f4,f6,f5\n1,2,3,11,13,12\n4,5,6,11,13,12\n7,8,9,11,13,12\n", "output (with eval, multiple fields)");
    $stdout = capture_stdout { $res = App::CSVUtils::csv_add_fields::csv_add_fields(input_filename=>"$dir/1.csv", fields=>["f4"], eval=>'$main::rownum*2', after=>'f1') };
    is($stdout, "f1,f4,f2,f3\n1,4,2,3\n4,6,5,6\n7,8,8,9\n", "output (with 'after' option)");
    $stdout = capture_stdout { $res = App::CSVUtils::csv_add_fields::csv_add_fields(input_filename=>"$dir/1.csv", fields=>["f4"], eval=>'$main::rownum*2', before=>'f2') };
    is($stdout, "f1,f4,f2,f3\n1,4,2,3\n4,6,5,6\n7,8,8,9\n", "output (with 'before' option)");
    $stdout = capture_stdout { $res = App::CSVUtils::csv_add_fields::csv_add_fields(input_filename=>"$dir/1.csv", fields=>["f4"], eval=>'$main::rownum*2', at=>2) };
    is($stdout, "f1,f4,f2,f3\n1,4,2,3\n4,6,5,6\n7,8,8,9\n", "output (with 'at' option)");
};

subtest csv_delete_fields => sub {
    my ($res, $stdout);

    require App::CSVUtils::csv_delete_fields;

    $res = App::CSVUtils::csv_delete_fields::csv_delete_fields(input_filename=>"$dir/1.csv", include_fields=>["f4"]);
    is($res->[0], 400, "deleting unknown field -> error");

    subtest "deleting unknown field with ignore_unknown_fields option -> ok" => sub {
        $stdout = capture_stdout { $res = App::CSVUtils::csv_delete_fields::csv_delete_fields(input_filename=>"$dir/1.csv", include_fields=>["f4"], ignore_unknown_fields=>1) };
        is($stdout, "f1,f2,f3\n1,2,3\n4,5,6\n7,8,9\n");
    };

    subtest "exclude_field_pat option" => sub {
        $stdout = capture_stdout { $res = App::CSVUtils::csv_delete_fields::csv_delete_fields(input_filename=>"$dir/1.csv", include_field_pat => qr/.*/, exclude_field_pat=>qr/3/) };
        is($stdout, "f3\n3\n6\n9\n");
    };

    subtest "exclude_fields option" => sub {
        $stdout = capture_stdout { $res = App::CSVUtils::csv_delete_fields::csv_delete_fields(input_filename=>"$dir/1.csv", include_field_pat => qr/.*/, exclude_fields=>['f3']) };
        is($stdout, "f3\n3\n6\n9\n");
    };

    subtest "show_selected_fields option" => sub {
        $res = App::CSVUtils::csv_delete_fields::csv_delete_fields(input_filename=>"$dir/1.csv", include_field_pat => qr/.*/, exclude_fields=>['f3'], show_selected_fields=>1);
        is_deeply($res, [200, "OK", ["f1","f2"]]) or diag explain $res;
    };

    $res = App::CSVUtils::csv_delete_fields::csv_delete_fields(input_filename=>"$dir/2.csv", include_field_pat=>qr/.*/);
    is($res->[0], 412, "deleting last remaining field -> error (1)");

    $res = App::CSVUtils::csv_delete_fields::csv_delete_fields(input_filename=>"$dir/3.csv", include_fields=>["f2", "f1"]);
    is($res->[0], 412, "deleting last remaining field -> error (2)");

    subtest "include_fields (1)" => sub {
        $stdout = capture_stdout { $res = App::CSVUtils::csv_delete_fields::csv_delete_fields(input_filename=>"$dir/1.csv", include_fields=>["f1"]) };
        is($stdout, "f2,f3\n2,3\n5,6\n8,9\n", "output");
    };

    subtest "include_fields (2)" => sub {
        $stdout = capture_stdout { $res = App::CSVUtils::csv_delete_fields::csv_delete_fields(input_filename=>"$dir/1.csv", include_fields=>["f3", "f1"]) };
        is($stdout, "f2\n2\n5\n8\n");
    };
};

subtest csv_list_field_names => sub {
    my ($res, $stdout);

    require App::CSVUtils::csv_list_field_names;

    $res = App::CSVUtils::csv_list_field_names::csv_list_field_names(input_filename=>"$dir/1.csv");
    is_deeply($res, [200,"OK",[{name=>'f1',index=>1},{name=>'f2',index=>2},{name=>'f3',index=>3}],{'table.fields'=>[qw/name index/]}], "result");
};

subtest csv_munge_field => sub {
    my ($res, $stdout);

    require App::CSVUtils::csv_munge_field;

    $res = App::CSVUtils::csv_munge_field::csv_munge_field(input_filename=>"$dir/1.csv", field=>"f1", eval=>"blah +");
    is($res->[0], 400, "error in code -> error");

    $res = App::CSVUtils::csv_munge_field::csv_munge_field(input_filename=>"$dir/1.csv", field=>"f4", eval=>'1');
    is($res->[0], 404, "munging unknown field -> error");

    $stdout = capture_stdout { $res = App::CSVUtils::csv_munge_field::csv_munge_field(input_filename=>"$dir/1.csv", field=>"f3", eval=>'$_ = $_*3') };
    is($stdout, "f1,f2,f3\n1,2,9\n4,5,18\n7,8,27\n", "output");
};

subtest csv_munge_row => sub {
    my ($res, $stdout);

    require App::CSVUtils::csv_munge_row;

    $res = App::CSVUtils::csv_munge_row::csv_munge_row(input_filename=>"$dir/1.csv", eval=>"blah +");
    is($res->[0], 400, "error in code -> error");

    $stdout = capture_stdout { $res = App::CSVUtils::csv_munge_row::csv_munge_row(input_filename=>"$dir/1.csv", eval=>'$_->[2] *= 3') };
    is($stdout, "f1,f2,f3\n1,2,9\n4,5,18\n7,8,27\n", "output");

    $stdout = capture_stdout { $res = App::CSVUtils::csv_munge_row::csv_munge_row(input_filename=>"$dir/1.csv", hash=>1, eval=>'$_->{f3} *= 3; delete $_->{f1}; $_->{f4} = 1') };
    is($stdout, "f1,f2,f3\n,2,9\n,5,18\n,8,27\n", "output (with --hash, new fields ignored)");
};

subtest csv_replace_newline => sub {
    my $res;

    $res = App::CSVUtils::csv_replace_newline(input_filename=>"$dir/3.csv", with=>" ");
    is_deeply($res, [200,"OK",qq(f1,f2\n1,"row 1"\n2,"row 2"\n),{'cmdline.skip_format'=>1}], "result");
    # XXX opt=with
};

subtest csv_sort_fields => sub {
    my $res;

    # alphabetical
    $res = App::CSVUtils::csv_sort_fields(input_filename=>"$dir/4.csv");
    is_deeply($res, [200,"OK",qq(F3,f1,f2\n2,1,3\n5,4,6\n),{'cmdline.skip_format'=>1}], "result (alphabetical)");
    # reverse alphabetical
    $res = App::CSVUtils::csv_sort_fields(input_filename=>"$dir/4.csv", reverse=>1);
    is_deeply($res, [200,"OK",qq(f2,f1,F3\n3,1,2\n6,4,5\n),{'cmdline.skip_format'=>1}], "result (reverse alphabetical)");
    # ci alphabetical
    $res = App::CSVUtils::csv_sort_fields(input_filename=>"$dir/4.csv", ci=>1);
    is_deeply($res, [200,"OK",qq(f1,f2,F3\n1,3,2\n4,6,5\n),{'cmdline.skip_format'=>1}], "result (ci alphabetical)");
    # by_examples
    $res = App::CSVUtils::csv_sort_fields(input_filename=>"$dir/4.csv", by_examples=>["f2","F3","f1"]);
    is_deeply($res, [200,"OK",qq(f2,F3,f1\n3,2,1\n6,5,4\n),{'cmdline.skip_format'=>1}], "result (by_examples)");
    # reverse by_examples
    $res = App::CSVUtils::csv_sort_fields(input_filename=>"$dir/4.csv", by_examples=>["f2","F3","f1"], reverse=>1);
    is_deeply($res, [200,"OK",qq(f1,F3,f2\n1,2,3\n4,5,6\n),{'cmdline.skip_format'=>1}], "result (reverse by_example)");
    # by_code
    $res = App::CSVUtils::csv_sort_fields(input_filename=>"$dir/4.csv", by_code=>sub { lc($a) cmp lc($b) });
    is_deeply($res, [200,"OK",qq(f1,f2,F3\n1,3,2\n4,6,5\n),{'cmdline.skip_format'=>1}], "result (by_code)");
    # by_sortsub
    subtest by_sortsub => sub {
        test_needs 'Sort::Sub', 'Sort::Sub::by_length';
        $res = App::CSVUtils::csv_sort_fields(input_filename=>"$dir/sort-fields.csv", by_sortsub=>"by_length");
        is_deeply($res, [200,"OK",qq(two,four,eighteen\n2,4,18\n),{'cmdline.skip_format'=>1}], "result (by sortsub)");
    };
};

subtest csv_sort_rows => sub {
    my $res;

    # alphabetical
    $res = App::CSVUtils::csv_sort_rows(input_filename=>"$dir/sort-rows.csv", by_fields=>["f2"]);
    is_deeply($res, [200,"OK",qq(f1,f2\n1,Andy\n10,Chuck\n2,andy\n),{'cmdline.skip_format'=>1}]);
    # reverse alphabetical
    $res = App::CSVUtils::csv_sort_rows(input_filename=>"$dir/sort-rows.csv", by_fields=>["~f2"]);
    is_deeply($res, [200,"OK",qq(f1,f2\n2,andy\n10,Chuck\n1,Andy\n),{'cmdline.skip_format'=>1}]);
    # numeric
    $res = App::CSVUtils::csv_sort_rows(input_filename=>"$dir/sort-rows.csv", by_fields=>["+f1"]);
    is_deeply($res, [200,"OK",qq(f1,f2\n1,Andy\n2,andy\n10,Chuck\n),{'cmdline.skip_format'=>1}]);
    # reverse numeric
    $res = App::CSVUtils::csv_sort_rows(input_filename=>"$dir/sort-rows.csv", by_fields=>["-f1"]);
    is_deeply($res, [200,"OK",qq(f1,f2\n10,Chuck\n2,andy\n1,Andy\n),{'cmdline.skip_format'=>1}]);
    # ci
    $res = App::CSVUtils::csv_sort_rows(input_filename=>"$dir/sort-rows.csv", by_fields=>["f2","+f1"], ci=>1);
    is_deeply($res, [200,"OK",qq(f1,f2\n1,Andy\n2,andy\n10,Chuck\n),{'cmdline.skip_format'=>1}]);

    # by code
    $res = App::CSVUtils::csv_sort_rows(input_filename=>"$dir/sort-rows.csv", by_code=>'$a->[0] cmp $b->[0]');
    is_deeply($res, [200,"OK",qq(f1,f2\n1,Andy\n10,Chuck\n2,andy\n),{'cmdline.skip_format'=>1}]);
    # by code, hash
    $res = App::CSVUtils::csv_sort_rows(input_filename=>"$dir/sort-rows.csv", by_code=>'$a->{f1} cmp $b->{f1}', hash=>1);
    is_deeply($res, [200,"OK",qq(f1,f2\n1,Andy\n10,Chuck\n2,andy\n),{'cmdline.skip_format'=>1}]);
    # by code, key
    $res = App::CSVUtils::csv_sort_rows(input_filename=>"$dir/sort-rows.csv", by_code=>'$a cmp $b', key=>'$_->[0]');
    is_deeply($res, [200,"OK",qq(f1,f2\n1,Andy\n10,Chuck\n2,andy\n),{'cmdline.skip_format'=>1}]);
    # by code, hash, key
    $res = App::CSVUtils::csv_sort_rows(input_filename=>"$dir/sort-rows.csv", by_code=>'$a cmp $b', hash=>1, key=>'$_->{f1}');
    is_deeply($res, [200,"OK",qq(f1,f2\n1,Andy\n10,Chuck\n2,andy\n),{'cmdline.skip_format'=>1}]);

    subtest by_sortsub => sub {
        test_needs 'Sort::Sub', 'Sort::Sub::numerically';
        # numeric
        $res = App::CSVUtils::csv_sort_rows(input_filename=>"$dir/sort-rows.csv", by_sortsub=>"numerically", key=>'$_->[0]');
        is_deeply($res, [200,"OK",qq(f1,f2\n1,Andy\n2,andy\n10,Chuck\n),{'cmdline.skip_format'=>1}]);
        # reverse numeric. hash
        $res = App::CSVUtils::csv_sort_rows(input_filename=>"$dir/sort-rows.csv", by_sortsub=>"numerically<r>", hash=>1, key=>'$_->{f1}');
        is_deeply($res, [200,"OK",qq(f1,f2\n10,Chuck\n2,andy\n1,Andy\n),{'cmdline.skip_format'=>1}]);
    };
};

subtest csv_sum => sub {
    my ($res, $stdout);

    require App::CSVUtils::csv_sum;

    $stdout = capture_stdout { $res = App::CSVUtils::csv_sum::csv_sum(input_filename=>"$dir/4.csv") };
    is($stdout, qq(f1,F3,f2\n5,7,9\n), "result");
    $stdout = capture_stdout { $res = App::CSVUtils::csv_sum::csv_sum(input_filename=>"$dir/4.csv", with_data_rows=>1) };
    is($stdout, qq(f1,F3,f2\n1,2,3\n4,5,6\n5,7,9\n), "output (with_data_rows=1)");
    $stdout = capture_stdout { $res = App::CSVUtils::csv_sum::csv_sum(input_filename=>"$dir/no-rows.csv") };
    is($stdout, qq(f1,f2,f3\n0,0,0\n), "output (no rows)");
};

subtest csv_avg => sub {
    my ($res, $stdout);

    require App::CSVUtils::csv_avg;

    $stdout = capture_stdout { $res = App::CSVUtils::csv_avg::csv_avg(input_filename=>"$dir/4.csv") };
    is($stdout, qq(f1,F3,f2\n2.5,3.5,4.5\n), "output");
    $stdout = capture_stdout { $res = App::CSVUtils::csv_avg::csv_avg(input_filename=>"$dir/4.csv", with_data_rows=>1) };
    is($stdout, qq(f1,F3,f2\n1,2,3\n4,5,6\n2.5,3.5,4.5\n), "output (with_data_rows=1)");
    $stdout = capture_stdout { $res = App::CSVUtils::csv_avg::csv_avg(input_filename=>"$dir/no-rows.csv") };
    is($stdout, qq(f1,f2,f3\n0,0,0\n), "output (no rows)");
};

subtest csv_select_rows => sub {
    my $res;

    $res = App::CSVUtils::csv_select_rows(input_filename=>"$dir/5.csv", row_spec=>'10');
    is_deeply($res, [200,"OK",qq(f1\n),{'cmdline.skip_format'=>1}], "result (n, outside range)");
    $res = App::CSVUtils::csv_select_rows(input_filename=>"$dir/5.csv", row_spec=>'4');
    is_deeply($res, [200,"OK",qq(f1\n3\n),{'cmdline.skip_format'=>1}], "result (n)");
    $res = App::CSVUtils::csv_select_rows(input_filename=>"$dir/5.csv", row_spec=>'4-6');
    is_deeply($res, [200,"OK",qq(f1\n3\n4\n5\n),{'cmdline.skip_format'=>1}], "result (n-m)");
    $res = App::CSVUtils::csv_select_rows(input_filename=>"$dir/5.csv", row_spec=>'2,4-6');
    is_deeply($res, [200,"OK",qq(f1\n1\n3\n4\n5\n),{'cmdline.skip_format'=>1}], "result (n1,n2-m)");
    $res = App::CSVUtils::csv_select_rows(input_filename=>"$dir/5.csv", row_spec=>'1-');
    is($res->[0], 400, "error in spec -> status 400");
};

subtest csv_convert_to_hash => sub {
    my $res;

    $res = App::CSVUtils::csv_convert_to_hash(input_filename=>"$dir/1.csv");
    is_deeply($res, [200,"OK",{f1=>1, f2=>2, f3=>3}], "result 1");
    $res = App::CSVUtils::csv_convert_to_hash(input_filename=>"$dir/1.csv", row_number=>3);
    is_deeply($res, [200,"OK",{f1=>4, f2=>5, f3=>6}], "result 2");
    $res = App::CSVUtils::csv_convert_to_hash(input_filename=>"$dir/1.csv", row_number=>10);
    is_deeply($res, [200,"OK",{f1=>undef, f2=>undef, f3=>undef}], "result 3");
};

subtest csv_concat => sub {
    my ($res, $stdout);

    require App::CSVUtils::csv_concat;
    $stdout = capture_stdout { $res = App::CSVUtils::csv_concat::csv_concat(input_filenames=>["$dir/1.csv","$dir/2.csv","$dir/4.csv"]) };
    is($stdout, qq(f1,f2,f3,F3\n1,2,3,\n4,5,6,\n7,8,9,\n1,,,\n2,,,\n3,,,\n1,3,,2\n4,6,,5\n), "output");
};

subtest csv_select_fields => sub {
    my ($res, $stdout);

    require App::CSVUtils::csv_select_fields;

    $res = App::CSVUtils::csv_select_fields::csv_select_fields(input_filename=>"$dir/1.csv", include_fields=>["f1", "f4"]);
    is($res->[0], 400, "specifying unknown field -> error");

    subtest "specifying unknown field with ignore_unknown_fields option -> ok" => sub {
        $stdout = capture_stdout { $res = App::CSVUtils::csv_select_fields::csv_select_fields(input_filename=>"$dir/1.csv", include_fields=>["f1", "f4"], ignore_unknown_fields=>1) };
        is($stdout, "f1\n1\n4\n7\n", "output");
    };

    subtest "ordering of fields as specified" => sub {
        $stdout = capture_stdout { $res = App::CSVUtils::csv_select_fields::csv_select_fields(input_filename=>"$dir/1.csv", include_fields=>["f3", "f1"]) };
        is($stdout, "f3,f1\n3,1\n6,4\n9,7\n", "output");
    };

    # XXX test include_field_pat, exclude_fields, exclude_field_pat (but these
    # are already tested in testing csv_delete_fields().

    # XXX test show_selected_fields (but this is already testing in testing
    # csv_delete_fields()).
};

subtest csv_grep => sub {
    my ($res, $stdout);

    require App::CSVUtils::csv_grep;

    $stdout = capture_stdout { $res = App::CSVUtils::csv_grep::csv_grep(input_filename=>"$dir/1.csv", eval=>'$_->[0] >= 4') };
    is($stdout, "f1,f2,f3\n4,5,6\n7,8,9\n", "output");
    subtest "opt: --hash" => sub {
        $stdout = capture_stdout { $res = App::CSVUtils::csv_grep::csv_grep(input_filename=>"$dir/1.csv", hash=>1, eval=>'$_->{f1} >= 4') };
        is($stdout, "f1,f2,f3\n4,5,6\n7,8,9\n", "output");
    };
    subtest "opt: --no-input-header" => sub {
        $stdout = capture_stdout { $res = App::CSVUtils::csv_grep::csv_grep(input_filename=>"$dir/no-header-1.csv", input_header=>0, eval=>'$_->[0] >= 4') };
        is($stdout, "4,5,6\n7,8,9\n", "output");
    };
    subtest "opt: --hash, --no-input-header" => sub {
        $stdout = capture_stdout { $res = App::CSVUtils::csv_grep::csv_grep(input_filename=>"$dir/no-header-1.csv", hash=>1, input_header=>0, eval=>'$_->{field1} >= 4') };
        is($stdout, "4,5,6\n7,8,9\n", "output");
    };
};

subtest csv_map => sub {
    my ($res, $stdout);

    require App::CSVUtils::csv_map;

    $stdout = capture_stdout { $res = App::CSVUtils::csv_map::csv_map(input_filename=>"$dir/1.csv", eval=>'"$_->[0].$_->[1].$_->[2]"') };
    is($stdout, "1.2.3\n4.5.6\n7.8.9\n", "output");
    subtest "opt: --hash" => sub {
        $stdout = capture_stdout { $res = App::CSVUtils::csv_map::csv_map(hash=>1, input_filename=>"$dir/1.csv", eval=>'"$_->{f1}.$_->{f2}.$_->{f3}"') };
        is($stdout, "1.2.3\n4.5.6\n7.8.9\n", "output");
    };
    subtest "opt: --no-add-newline" => sub {
        $stdout = capture_stdout { $res = App::CSVUtils::csv_map::csv_map(add_newline=>0, hash=>1, input_filename=>"$dir/1.csv", eval=>'"$_->{f1}.$_->{f2}.$_->{f3}"') };
        is($stdout, "1.2.34.5.67.8.9", "output");
    };
};

subtest csv_each_row => sub {
    my ($res, $stdout);

    require App::CSVUtils::csv_each_row;

    $stdout = capture_stdout { $res = App::CSVUtils::csv_each_row::csv_each_row(input_filename=>"$dir/1.csv", eval=>'print "$_->[0].$_->[1].$_->[2]\n"') };
    is($stdout, "1.2.3\n4.5.6\n7.8.9\n", "output");
    subtest "opt: --hash" => sub {
        $stdout = capture_stdout { $res = App::CSVUtils::csv_each_row::csv_each_row(hash=>1, input_filename=>"$dir/1.csv", eval=>'print "$_->{f1}.$_->{f2}.$_->{f3}\n"') };
        is($stdout, "1.2.3\n4.5.6\n7.8.9\n", "output");
    };
};

subtest csv_dump => sub {
    my $res;

    require App::CSVUtils::csv_dump;

    $res = App::CSVUtils::csv_dump::csv_dump(input_filename=>"$dir/1.csv");
    is_deeply($res, [200,"OK",[["f1","f2","f3"],[1,2,3],[4,5,6],[7,8,9]]])
        or diag explain $res;

    $res = App::CSVUtils::csv_dump::csv_dump(input_filename=>"$dir/1.tsv", input_tsv=>1);
    is_deeply($res, [200,"OK",[["f1","f2","f3"],[1,2,3],[4,5,6],[7,8,9]]])
        or diag explain $res;

    $res = App::CSVUtils::csv_dump::csv_dump(input_filename=>"$dir/1.csv", hash=>1);
    is_deeply($res, [200,"OK",[{f1=>1,f2=>2,f3=>3},{f1=>4,f2=>5,f3=>6},{f1=>7,f2=>8,f3=>9}]])
        or diag explain $res;

    $res = App::CSVUtils::csv_dump::csv_dump(input_filename=>"$dir/1.csv", input_header=>0);
    is_deeply($res, [200,"OK",[["field1","field2","field3"],["f1","f2","f3"],[1,2,3],[4,5,6],[7,8,9]]])
        or diag explain $res;

    $res = App::CSVUtils::csv_dump::csv_dump(input_filename=>"$dir/1.csv", input_header=>0, hash=>1);
    is_deeply($res, [200,"OK",[{field1=>'f1',field2=>'f2',field3=>'f3'},{field1=>1,field2=>2,field3=>3},{field1=>4,field2=>5,field3=>6},{field1=>7,field2=>8,field3=>9}]])
        or diag explain $res;

};

subtest csv_setop => sub {
    write_text("$dir/setop1.csv", "f1,f2,f3\nv1,v2,v3\nv4,v5,v6\nv7,v8,v9\n");
    write_text("$dir/setop2.csv", "f1,f2,f3\nv1,v2,v3\nv4,V5,v7\nv7,v8,v9\n");

    my $res;

    subtest intersect => sub {
        $res = App::CSVUtils::csv_setop(op=>"intersect", input_filenames=>["$dir/setop1.csv", "$dir/setop2.csv"]);
        is($res->[2], "f1,f2,f3\nv1,v2,v3\nv7,v8,v9\n");

        $res = App::CSVUtils::csv_setop(op=>"intersect", input_filenames=>["$dir/setop1.csv", "$dir/setop2.csv"], compare_fields=>"f1");
        is($res->[2], "f1,f2,f3\nv1,v2,v3\nv4,v5,v6\nv7,v8,v9\n", "opt:compare_fields");

        $res = App::CSVUtils::csv_setop(op=>"intersect", input_filenames=>["$dir/setop1.csv", "$dir/setop2.csv"], compare_fields=>"f1,f2", ignore_case=>1);
        is($res->[2], "f1,f2,f3\nv1,v2,v3\nv4,v5,v6\nv7,v8,v9\n", "opt:ignore_case");

        $res = App::CSVUtils::csv_setop(op=>"intersect", input_filenames=>["$dir/setop1.csv", "$dir/setop2.csv"], result_fields=>"f2,f1");
        is($res->[2], "f2,f1\nv2,v1\nv8,v7\n", "opt:result_fields");
    };

    subtest union => sub {
        $res = App::CSVUtils::csv_setop(op=>"union", input_filenames=>["$dir/setop1.csv", "$dir/setop2.csv"]);
        is($res->[2], "f1,f2,f3\nv1,v2,v3\nv4,v5,v6\nv7,v8,v9\nv4,V5,v7\n");

        $res = App::CSVUtils::csv_setop(op=>"union", input_filenames=>["$dir/setop1.csv", "$dir/setop2.csv"], compare_fields=>"f1");
        is($res->[2], "f1,f2,f3\nv1,v2,v3\nv4,v5,v6\nv7,v8,v9\n", "opt:compare_fields");

        $res = App::CSVUtils::csv_setop(op=>"union", input_filenames=>["$dir/setop1.csv", "$dir/setop2.csv"], compare_fields=>"f1,f2", ignore_case=>1);
        is($res->[2], "f1,f2,f3\nv1,v2,v3\nv4,v5,v6\nv7,v8,v9\n", "opt:ignore_case");

        $res = App::CSVUtils::csv_setop(op=>"union", input_filenames=>["$dir/setop1.csv", "$dir/setop2.csv"], compare_fields=>"f1", result_fields=>"f2,f1");
        is($res->[2], "f2,f1\nv2,v1\nv5,v4\nv8,v7\n", "opt:result_fields");
    };

    subtest diff => sub {
        $res = App::CSVUtils::csv_setop(op=>"diff", input_filenames=>["$dir/setop1.csv", "$dir/setop2.csv"]);
        is($res->[2], "f1,f2,f3\nv4,v5,v6\n");

        $res = App::CSVUtils::csv_setop(op=>"diff", input_filenames=>["$dir/setop1.csv", "$dir/setop2.csv"], compare_fields=>"f1");
        is($res->[2], "f1,f2,f3\n", "opt:compare_fields");

        $res = App::CSVUtils::csv_setop(op=>"diff", input_filenames=>["$dir/setop1.csv", "$dir/setop2.csv"], compare_fields=>"f1,f2", ignore_case=>1);
        is($res->[2], "f1,f2,f3\n", "opt:ignore_case");

        $res = App::CSVUtils::csv_setop(op=>"diff", input_filenames=>["$dir/setop1.csv", "$dir/setop2.csv"], result_fields=>"f2,f1");
        is($res->[2], "f2,f1\nv5,v4\n", "opt:result_fields");
    };

    subtest symdiff => sub {
        $res = App::CSVUtils::csv_setop(op=>"symdiff", input_filenames=>["$dir/setop1.csv", "$dir/setop2.csv"]);
        is($res->[2], "f1,f2,f3\nv4,v5,v6\nv4,V5,v7\n");

        $res = App::CSVUtils::csv_setop(op=>"symdiff", input_filenames=>["$dir/setop1.csv", "$dir/setop2.csv"], compare_fields=>"f1");
        is($res->[2], "f1,f2,f3\n", "opt:compare_fields");

        $res = App::CSVUtils::csv_setop(op=>"symdiff", input_filenames=>["$dir/setop1.csv", "$dir/setop2.csv"], compare_fields=>"f1,f2", ignore_case=>1);
        is($res->[2], "f1,f2,f3\n", "opt:ignore_case");

        $res = App::CSVUtils::csv_setop(op=>"symdiff", input_filenames=>["$dir/setop1.csv", "$dir/setop2.csv"], result_fields=>"f3,f1");
        is($res->[2], "f3,f1\nv6,v4\nv7,v4\n", "opt:result_fields");
    };
};

subtest csv_lookup_fields => sub {
    write_text("$dir/report.csv", <<'_');
client_id,followup_staff,followup_note,client_email,client_phone
101,Jerry,not renewing,
299,Jerry,still thinking over,
734,Elaine,renewing,
_

    write_text("$dir/clients.csv", <<'_');
id,name,email,client_phone
101,Andy,andy@example.com,555-2983
102,Bob,bob@acme.example.com,555-2523
299,Cindy,cindy@example.com,555-7892
400,Derek,derek@example.com,555-9018
701,Edward,edward@example.com,555-5833
734,Felipe,felipe@example.com,555-9067
_

    my $res;

    $res = App::CSVUtils::csv_lookup_fields(target=>"$dir/report.csv", source=>"$dir/clients.csv", lookup_fields=>"client_id:id", fill_fields=>"client_email:email,client_phone");
    is($res->[2], <<'_');
client_id,followup_staff,followup_note,client_email,client_phone
101,Jerry,"not renewing",andy@example.com,555-2983
299,Jerry,"still thinking over",cindy@example.com,555-7892
734,Elaine,renewing,felipe@example.com,555-9067
_

    # XXX test opt:ignore_case
};

subtest "csv_csv" => sub {
    # TODO
    ok 1;
};

done_testing;
