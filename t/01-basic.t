#!perl

use 5.010001;
use strict;
use warnings;
use Test::Exception;
use Test::More 0.98;

use App::CSVUtils;
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

# XXX test with opt: --no-header

subtest csv_add_field => sub {
    my $res;

    dies_ok { App::CSVUtils::csv_add_field(filename=>"$dir/1.csv", field=>"f4", eval=>"blah +") }
        "error in eval code -> dies";

    $res = App::CSVUtils::csv_add_field(filename=>"$dir/1.csv", field=>"f3", eval=>"1");
    is($res->[0], 412, "adding existing field -> error");

    $res = App::CSVUtils::csv_add_field(filename=>"$dir/1.csv", field=>"", eval=>"1");
    is($res->[0], 400, "empty field -> error");

    $res = App::CSVUtils::csv_add_field(filename=>"$dir/1.csv", field=>"f4", eval=>'$main::rownum*2');
    is_deeply($res, [200,"OK","f1,f2,f3,f4\n1,2,3,4\n4,5,6,6\n7,8,9,8\n",{'cmdline.skip_format'=>1}], "result");
    $res = App::CSVUtils::csv_add_field(filename=>"$dir/1.csv", field=>"f4", eval=>'$main::rownum*2', after=>'f1');
    is_deeply($res, [200,"OK","f1,f4,f2,f3\n1,4,2,3\n4,6,5,6\n7,8,8,9\n",{'cmdline.skip_format'=>1}], "result (with 'after' option)");
    $res = App::CSVUtils::csv_add_field(filename=>"$dir/1.csv", field=>"f4", eval=>'$main::rownum*2', before=>'f2');
    is_deeply($res, [200,"OK","f1,f4,f2,f3\n1,4,2,3\n4,6,5,6\n7,8,8,9\n",{'cmdline.skip_format'=>1}], "result (with 'before' option)");
    $res = App::CSVUtils::csv_add_field(filename=>"$dir/1.csv", field=>"f4", eval=>'$main::rownum*2', at=>2);
    is_deeply($res, [200,"OK","f1,f4,f2,f3\n1,4,2,3\n4,6,5,6\n7,8,8,9\n",{'cmdline.skip_format'=>1}], "result (with 'at' option)");
};

subtest csv_delete_field => sub {
    my $res;

    dies_ok { App::CSVUtils::csv_delete_field(filename=>"$dir/1.csv", fields=>["f4"]) }
        "deleting unknown field -> dies (1)";

    dies_ok { App::CSVUtils::csv_delete_field(filename=>"$dir/1.csv", fields=>["f1", "f4"]) }
        "deleting unknown field -> dies (2)";

    $res = App::CSVUtils::csv_delete_field(filename=>"$dir/2.csv", fields=>["f1"]);
    is($res->[0], 412, "deleting last remaining field -> error (1)");

    $res = App::CSVUtils::csv_delete_field(filename=>"$dir/3.csv", fields=>["f2", "f1"]);
    is($res->[0], 412, "deleting last remaining field -> error (2)");

    $res = App::CSVUtils::csv_delete_field(filename=>"$dir/1.csv", fields=>["f1"]);
    is_deeply($res, [200,"OK","f2,f3\n2,3\n5,6\n8,9\n",{'cmdline.skip_format'=>1}], "result");

    $res = App::CSVUtils::csv_delete_field(filename=>"$dir/1.csv", fields=>["f3", "f1"]);
    is_deeply($res, [200,"OK","f2\n2\n5\n8\n",{'cmdline.skip_format'=>1}], "result")
        or diag explain $res;
};

subtest csv_list_field_names => sub {
    my $res;

    $res = App::CSVUtils::csv_list_field_names(filename=>"$dir/1.csv");
    is_deeply($res, [200,"OK",[{name=>'f1',index=>1},{name=>'f2',index=>2},{name=>'f3',index=>3}],{'table.fields'=>[qw/name index/]}], "result");
};

subtest csv_munge_field => sub {
    my $res;

    dies_ok { App::CSVUtils::csv_munge_field(filename=>"$dir/1.csv", field=>"f1", eval=>"blah +") }
        "error in code -> dies";

    dies_ok { App::CSVUtils::csv_munge_field(filename=>"$dir/1.csv", field=>"f4", eval=>'1') }
        "munging unknown field -> dies";

    $res = App::CSVUtils::csv_munge_field(filename=>"$dir/1.csv", field=>"f3", eval=>'$_ = $_*3');
    is_deeply($res, [200,"OK","f1,f2,f3\n1,2,9\n4,5,18\n7,8,27\n",{'cmdline.skip_format'=>1}], "result");
};

subtest csv_replace_newline => sub {
    my $res;

    $res = App::CSVUtils::csv_replace_newline(filename=>"$dir/3.csv", with=>" ");
    is_deeply($res, [200,"OK",qq(f1,f2\n1,"row 1"\n2,"row 2"\n),{'cmdline.skip_format'=>1}], "result");
    # XXX opt=with
};

subtest csv_sort_fields => sub {
    my $res;

    # alphabetical
    $res = App::CSVUtils::csv_sort_fields(filename=>"$dir/4.csv");
    is_deeply($res, [200,"OK",qq(F3,f1,f2\n2,1,3\n5,4,6\n),{'cmdline.skip_format'=>1}], "result (alphabetical)");
    # reverse alphabetical
    $res = App::CSVUtils::csv_sort_fields(filename=>"$dir/4.csv", reverse=>1);
    is_deeply($res, [200,"OK",qq(f2,f1,F3\n3,1,2\n6,4,5\n),{'cmdline.skip_format'=>1}], "result (reverse alphabetical)");
    # ci alphabetical
    $res = App::CSVUtils::csv_sort_fields(filename=>"$dir/4.csv", ci=>1);
    is_deeply($res, [200,"OK",qq(f1,f2,F3\n1,3,2\n4,6,5\n),{'cmdline.skip_format'=>1}], "result (ci alphabetical)");
    # example
    $res = App::CSVUtils::csv_sort_fields(filename=>"$dir/4.csv", example=>["f2","F3","f1"]);
    is_deeply($res, [200,"OK",qq(f2,F3,f1\n3,2,1\n6,5,4\n),{'cmdline.skip_format'=>1}], "result (example)");
    # reverse example
    $res = App::CSVUtils::csv_sort_fields(filename=>"$dir/4.csv", example=>["f2","F3","f1"], reverse=>1);
    is_deeply($res, [200,"OK",qq(f1,F3,f2\n1,2,3\n4,5,6\n),{'cmdline.skip_format'=>1}], "result (reverse example)");
};

subtest csv_sum => sub {
    my $res;

    $res = App::CSVUtils::csv_sum(filename=>"$dir/4.csv");
    is_deeply($res, [200,"OK",qq(f1,F3,f2\n5,7,9\n),{'cmdline.skip_format'=>1}], "result");
    $res = App::CSVUtils::csv_sum(filename=>"$dir/4.csv", with_data_rows=>1);
    is_deeply($res, [200,"OK",qq(f1,F3,f2\n1,2,3\n4,5,6\n5,7,9\n),{'cmdline.skip_format'=>1}], "result (with_data_rows=1)");
    $res = App::CSVUtils::csv_sum(filename=>"$dir/no-rows.csv");
    is_deeply($res, [200,"OK",qq(f1,f2,f3\n0,0,0\n),{'cmdline.skip_format'=>1}], "result (no rows)");
};

subtest csv_avg => sub {
    my $res;

    $res = App::CSVUtils::csv_avg(filename=>"$dir/4.csv");
    is_deeply($res, [200,"OK",qq(f1,F3,f2\n2.5,3.5,4.5\n),{'cmdline.skip_format'=>1}], "result");
    $res = App::CSVUtils::csv_avg(filename=>"$dir/4.csv", with_data_rows=>1);
    is_deeply($res, [200,"OK",qq(f1,F3,f2\n1,2,3\n4,5,6\n2.5,3.5,4.5\n),{'cmdline.skip_format'=>1}], "result (with_data_rows=1)");
    $res = App::CSVUtils::csv_avg(filename=>"$dir/no-rows.csv");
    is_deeply($res, [200,"OK",qq(f1,f2,f3\n0,0,0\n),{'cmdline.skip_format'=>1}], "result (no rows)");
};

subtest csv_select_row => sub {
    my $res;

    $res = App::CSVUtils::csv_select_row(filename=>"$dir/5.csv", row_spec=>'10');
    is_deeply($res, [200,"OK",qq(f1\n),{'cmdline.skip_format'=>1}], "result (n, outside range)");
    $res = App::CSVUtils::csv_select_row(filename=>"$dir/5.csv", row_spec=>'4');
    is_deeply($res, [200,"OK",qq(f1\n3\n),{'cmdline.skip_format'=>1}], "result (n)");
    $res = App::CSVUtils::csv_select_row(filename=>"$dir/5.csv", row_spec=>'4-6');
    is_deeply($res, [200,"OK",qq(f1\n3\n4\n5\n),{'cmdline.skip_format'=>1}], "result (n-m)");
    $res = App::CSVUtils::csv_select_row(filename=>"$dir/5.csv", row_spec=>'2,4-6');
    is_deeply($res, [200,"OK",qq(f1\n1\n3\n4\n5\n),{'cmdline.skip_format'=>1}], "result (n1,n2-m)");
    $res = App::CSVUtils::csv_select_row(filename=>"$dir/5.csv", row_spec=>'1-');
    is($res->[0], 400, "error in spec -> status 400");
};

subtest csv_convert_to_hash => sub {
    my $res;

    $res = App::CSVUtils::csv_convert_to_hash(filename=>"$dir/1.csv");
    is_deeply($res, [200,"OK",{f1=>1, f2=>2, f3=>3}], "result 1");
    $res = App::CSVUtils::csv_convert_to_hash(filename=>"$dir/1.csv", row_number=>3);
    is_deeply($res, [200,"OK",{f1=>4, f2=>5, f3=>6}], "result 2");
    $res = App::CSVUtils::csv_convert_to_hash(filename=>"$dir/1.csv", row_number=>10);
    is_deeply($res, [200,"OK",{f1=>undef, f2=>undef, f3=>undef}], "result 3");
};

subtest csv_concat => sub {
    my $res;

    $res = App::CSVUtils::csv_concat(filenames=>["$dir/1.csv","$dir/2.csv","$dir/4.csv"]);
    is_deeply($res, [200,"OK",qq(f1,f2,f3,F3\n1,2,3,\n4,5,6,\n7,8,9,\n1,,,\n2,,,\n3,,,\n1,3,,2\n4,6,,5\n),{'cmdline.skip_format'=>1}], "result");
};

subtest csv_select_fields => sub {
    my $res;

    dies_ok { App::CSVUtils::csv_select_fields(filename=>"$dir/1.csv", fields=>["f1", "f4"]) }
        "specifying unknown field -> dies";

    $res = App::CSVUtils::csv_select_fields(filename=>"$dir/1.csv", fields=>["f1", "f1"]);
    is($res->[0], 400, "duplicated field -> status 400");

    $res = App::CSVUtils::csv_select_fields(filename=>"$dir/1.csv", fields=>["f3", "f1"]);
    is_deeply($res, [200,"OK","f3,f1\n3,1\n6,4\n9,7\n",{'cmdline.skip_format'=>1}], "result")
        or diag explain $res;
};

subtest csv_grep => sub {
    my $res;

    $res = App::CSVUtils::csv_grep(filename=>"$dir/1.csv", eval=>'$_->[0] >= 4');
    is_deeply($res, [200,"OK","f1,f2,f3\n4,5,6\n7,8,9\n",{'cmdline.skip_format'=>1}], "result")
        or diag explain $res;
    subtest "opt: --hash" => sub {
        $res = App::CSVUtils::csv_grep(filename=>"$dir/1.csv", hash=>1, eval=>'$_->{f1} >= 4');
        is_deeply($res, [200,"OK","f1,f2,f3\n4,5,6\n7,8,9\n",{'cmdline.skip_format'=>1}], "result")
            or diag explain $res;
    };
    subtest "opt: --no-header" => sub {
        $res = App::CSVUtils::csv_grep(filename=>"$dir/no-header-1.csv", header=>0, eval=>'$_->[0] >= 4');
        is_deeply($res, [200,"OK","4,5,6\n7,8,9\n",{'cmdline.skip_format'=>1}], "result")
            or diag explain $res;
    };
    subtest "opt: --hash, --no-header" => sub {
        $res = App::CSVUtils::csv_grep(filename=>"$dir/no-header-1.csv", hash=>1, header=>0, eval=>'$_->{field1} >= 4');
        is_deeply($res, [200,"OK","4,5,6\n7,8,9\n",{'cmdline.skip_format'=>1}], "result")
            or diag explain $res;
    };
};

subtest csv_map => sub {
    my $res;

    $res = App::CSVUtils::csv_map(filename=>"$dir/1.csv", eval=>'"$_->[0].$_->[1].$_->[2]"');
    is_deeply($res, [200,"OK","1.2.3\n4.5.6\n7.8.9\n",{'cmdline.skip_format'=>1}], "result")
        or diag explain $res;
    subtest "opt: --hash" => sub {
        $res = App::CSVUtils::csv_map(hash=>1, filename=>"$dir/1.csv", eval=>'"$_->{f1}.$_->{f2}.$_->{f3}"');
        is_deeply($res, [200,"OK","1.2.3\n4.5.6\n7.8.9\n",{'cmdline.skip_format'=>1}], "result")
            or diag explain $res;
    };
    subtest "opt: --no-add-newline" => sub {
        $res = App::CSVUtils::csv_map(add_newline=>0, hash=>1, filename=>"$dir/1.csv", eval=>'"$_->{f1}.$_->{f2}.$_->{f3}"');
        is_deeply($res, [200,"OK","1.2.34.5.67.8.9",{'cmdline.skip_format'=>1}], "result")
            or diag explain $res;
    };
};

done_testing;
