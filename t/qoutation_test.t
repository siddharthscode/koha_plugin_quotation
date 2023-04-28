use Modern::Perl;

use Archive::Extract;
use CGI;
use Cwd qw(abs_path);
use File::Basename;
use File::Spec;
use File::Temp qw( tempdir tempfile );
use FindBin qw($Bin);
use Module::Load::Conditional qw(can_load);
use Test::MockModule;
use Test::More qw(no_plan);
use Test::Warn;

use C4::Context;
use Koha::Database;
use Koha::Plugins::Methods;

use t::lib::Mocks;
use t::lib::TestBuilder;

use C4::Letters qw( GetQueuedMessages GetMessage );
use C4::Budgets qw( AddBudgetPeriod AddBudget GetBudget );
use Koha::DateUtils qw( dt_from_string output_pref );
use Koha::Libraries;
use Koha::Patrons;
use Koha::Suggestions;

BEGIN {
    # Mock pluginsdir before loading Plugins module
    my $path = dirname(__FILE__) . '/../../../lib/plugins';
    t::lib::Mocks::mock_config( 'pluginsdir', $path );
    
    use_ok('C4::Suggestions', qw( NewSuggestion GetSuggestion ModSuggestion GetSuggestionInfo GetSuggestionFromBiblionumber GetSuggestionInfoFromBiblionumber GetSuggestionByStatus ConnectSuggestionAndBiblio DelSuggestion MarcRecordFromNewSuggestion GetUnprocessedSuggestions DelSuggestionsOlderThan ));
    use_ok('Koha::Plugins');
    use_ok('Koha::Plugins::Handler');
    use_ok('Koha::Plugins::Base');
    use_ok('Koha::Plugin::Test');
    use_ok('Koha::Plugin::TestItemBarcodeTransform');
}

my $schema = Koha::Database->new->schema;

# test begins

$schema->storage->txn_begin;
my $dbh = C4::Context->dbh;
my $builder = t::lib::TestBuilder->new;
#Koha::Plugins::Methods->delete;
$schema->resultset('PluginData')->delete();

#create a patron
my $patron_category = $builder->build({ source => 'Category' });
my $member = {
    firstname => 'my firstname',
    surname => 'my surname',
    categorycode => $patron_category->{categorycode},
    branchcode => 'CPL',
    smsalertnumber => 12345,
};
my $member2 = {
    firstname => 'my secondmember firstname',
    surname => 'my secondmember surname',
    categorycode => $patron_category->{categorycode},
    branchcode => 'CPL',
    email => 'to@example.com',
};
my $borrowernumber = Koha::Patron->new($member)->store->borrowernumber;
my $borrowernumber2 = Koha::Patron->new($member2)->store->borrowernumber;

#create suggestion
my $my_suggestion_checked = {
    title         => 'my title checked',
    author        => 'my author checked',
    publishercode => 'my publishercode checked',
    suggestedby   => $borrowernumber,
    biblionumber  => '',
    branchcode    => 'CPL',
    managedby     => '',
    manageddate   => '',
    accepteddate  => '',
    note          => 'my note',
    STATUS        => 'CHECKED',
    quantity      => '', # Insert an empty string into int to catch strict SQL modes errors
};
my $my_suggestion = {
    title         => 'my title',
    author        => 'my author',
    publishercode => 'my publishercode',
    suggestedby   => $borrowernumber2,
    biblionumber  => '',
    branchcode    => 'CPL',
    managedby     => '',
    manageddate   => '',
    accepteddate  => '',
    note          => 'my note',
    quantity      => '', # Insert an empty string into int to catch strict SQL modes errors
};
my $my_suggestionid = NewSuggestion($my_suggestion);
my $suggestion = GetSuggestion($my_suggestionid);
is( $suggestion->{title}, $my_suggestion->{title}, 'NewSuggestion stores the  correctly' );
is( $suggestion->{STATUS}, 'ASKED', 'NewSuggestion status is ASKED' );

my $my_suggestionid_checked = NewSuggestion($my_suggestion_checked);
my $suggestion_checked = GetSuggestion($my_suggestionid_checked);
is( $suggestion_checked->{title}, $my_suggestion_checked->{title}, 'checked status NewSuggestion stores the  correctly' );
is( $suggestion_checked->{STATUS}, 'CHECKED', 'checked NewSuggestion status is checked' );


for my $pass ( 1 .. 1 ) {
    my $plugins_dir;
    my $module_name = 'Koha::Plugin::qoutation';
    my $pm_path = 'Koha/Plugin/qoutation.pm';
    if ( $pass == 1 ) {
        my $plugins_dir1 = tempdir( CLEANUP => 1 );
        t::lib::Mocks::mock_config('pluginsdir', $plugins_dir1);
        $plugins_dir = $plugins_dir1;
        push @INC, $plugins_dir1;
    } else {
        my $plugins_dir1 = tempdir( CLEANUP => 1 );
        my $plugins_dir2 = tempdir( CLEANUP => 1 );
        t::lib::Mocks::mock_config('pluginsdir', [ $plugins_dir2, $plugins_dir1 ]);
        $plugins_dir = $plugins_dir2;
        pop @INC;
        push @INC, $plugins_dir2;
        push @INC, $plugins_dir1;
    }
    my $full_pm_path = $plugins_dir . '/' . $pm_path;

    my $ae = Archive::Extract->new( archive => "$Bin/Koha_plugin_qoutation_0.kpz", type => 'zip' );
    unless ( $ae->extract( to => $plugins_dir ) ) {
        warn "ERROR: " . $ae->error;
    }
    use_ok('Koha::Plugin::qoutation');
    my $plugin = Koha::Plugin::qoutation->new({ enable_plugins => 1});
#my $table = $plugin->get_qualified_table_name( 'mytable' );

    ok( -f $plugins_dir . "/Koha/Plugin/qoutation.pm", "Quotation plugin installed successfully" );
    $INC{$pm_path} = $full_pm_path; # FIXME I do not really know why, but if this is moved before the $plugin constructor, it will fail with Can't locate object method "new" via package "Koha::Plugin::Com::ByWaterSolutions::KitchenSink"
warning_is { Koha::Plugins->new( { enable_plugins => 1 } )->InstallPlugins(); } undef;

#--------------Use case testing starts--------------------------------------------#

#print "Use case 1: shows pending indents";
    #mock: creating indentation table
    my $table = "indentation_list_table";
    my $qq = "
         CREATE TABLE IF NOT EXISTS $table (
         `indentationid` VARCHAR(50) NOT NULL,
         `status` VARCHAR(50) DEFAULT 'pending',
          `suggestionid` INT(10) DEFAULT NULL
        ) ENGINE = INNODB;";
    my $sth = $dbh->prepare($qq);
    $sth->execute();
    $sth->finish();

    #mock: fill indentation table
    my $indentid = q{12LIB45678};
    my $qq11 = qq/
                INSERT INTO $table (indentationid, status, suggestionid) 
                VALUES (?, ?, ?)/;
    my $sth31 = $dbh->prepare($qq11);
    $sth31->execute($indentid, 'indentation generated', $my_suggestionid_checked);
    $sth31->finish();
    
    my $cgi = CGI->new;
    $cgi->param(-name=>'save', -value=>'0');
    local *STDOUT;
    my $stdout;
    open STDOUT, '>', \$stdout;
    Koha::Plugins::Handler->run({ class => "Koha::Plugin::qoutation", method => 'tool',enable_plugins=>1, cgi=>$cgi });
    like($stdout, qr{<td> <input type="checkbox" name="indent" value="$indentid" onclick="return ValidateSelection\(\);"> <\/td>}, 'Use case 1: shows quotation pending indents');

#warning_like {Koha::Plugins::Handler->run({ class => "Koha::Plugin::qoutation", method => 'tool',enable_plugins=>1, cgi=>$cgi });} qr{Exception}, q{Use case 1: qoutation tool fails without indentation plugin};
    
#Use case 2: displays suggestions of selected indents
    $cgi->param(-name=>'save', -value=>'1'); #clicked 'Generate Qoutation' button
    $cgi->param(-name=>'indent', -value=>[$indentid]); #selected indentid for quotation generation
    $stdout = '';
    close STDOUT;
    open STDOUT, '>', \$stdout;
    Koha::Plugins::Handler->run({ class => "Koha::Plugin::qoutation", method => 'tool',enable_plugins=>1, cgi=>$cgi });
    like($stdout, qr{<tr>\s*<td> $indentid <\/td>\s*<td> $suggestion_checked->{author}> <\/td>\s*}, 'Use case 2: displays suggestions of selected indents');



#Use case 3: 
#----------Use case testing completes----------------------------------------------#

    Koha::Plugins::Handler->delete({ class => "Koha::Plugin::qoutation", enable_plugins => 1 });
#my $sth = C4::Context->dbh->table_info( undef, undef, $table, 'TABLE' );
#my $info = $sth->fetchall_arrayref;
#is( @$info, 0, "Table $table does no longer exist" );
    ok( !( -f $full_pm_path ), "Koha::Plugins::Handler::delete works correctly (pass $pass)" );
}

$schema->storage->txn_rollback();
