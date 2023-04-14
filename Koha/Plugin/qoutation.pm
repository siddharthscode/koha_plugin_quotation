package Koha::Plugin::qoutation;

## It's good practice to use Modern::Perl
use Modern::Perl;

## Required for all plugins
use base qw(Koha::Plugins::Base);

## We will also need to include any Koha libraries we want to access
use C4::Auth;
use C4::Context;

use Koha::Account::Lines;
use Koha::Account;
use Koha::DateUtils;
use Koha::Libraries;
use Koha::Patron::Categories;
use Koha::Patron;

use Cwd qw(abs_path);
use Data::Dumper;
use LWP::UserAgent;
use MARC::Record;
use Mojo::JSON qw(decode_json);;
use URI::Escape qw(uri_unescape);


our $VERSION = "{VERSION}";

our $metadata = {
    name            => 'Qoutation plugin',
    author          => 'Siddharth',
    description     => 'Generate Qoutation',
    date_authored   => '2020-12-01',
    date_updated    => "1970-01-01",
    minimum_version => '19.1100000',
    maximum_version => undef,
    version         => $VERSION,
};

sub new {
    my ( $class, $args ) = @_;

    $args->{'metadata'} = $metadata;
    my $self = $class->SUPER::new($args);

    return $self;
}

sub report {
    my ( $self, $args ) = @_;
    
    my $cgi = $self->{'cgi'};
}

sub tool {
    
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};
     my @indentation_list;
     my @checked_list;
    
    unless ($cgi->param('save')){
        my $template = $self->get_template({ file => 'tool-step1.tt' });
        my $dbh = C4::Context->dbh;
        my $table = "indentation_list_table";

        # fetch all 'pending' indentations
        my $pending_indentation_query =  qq/
            SELECT DISTINCT $table.indentationid
            FROM $table
            WHERE status LIKE 'pending'
        /;
        my $sth = $dbh->prepare($pending_indentation_query);
        $sth->execute();
       
        
        while ( my $row = $sth->fetchrow_hashref() ) {
            push( @indentation_list, $row );
        }
        $template->param( indentation_list => \@indentation_list);
        $self->output_html($template->output());
        
        
    }
    else{
    		
        	@checked_list = $cgi->multi_param('indent');	
        
		my $template = $self->get_template({ file => 'tool-step2.tt' });
		my $dbh = C4::Context->dbh;
		my $table = "indentation_list_table";

		# fetch all 'checked' indentations
		my @idd_list;
			foreach my $idd (@checked_list){
				my $pending_indentation_query =  qq/
				    SELECT DISTINCT $table.indentationid, suggestions.suggestionid, suggestions.author, suggestions.title, suggestions.publicationyear
				    FROM $table , suggestions
				    WHERE $table.status LIKE 'pending'
				    AND $table.suggestionid LIKE suggestions.suggestionid 
				    AND $table.indentationid LIKE $idd
				/;
				my $sth = $dbh->prepare($pending_indentation_query);
				$sth->execute();
				
				while ( my $row = $sth->fetchrow_hashref() ) {
				    push( @idd_list, $row );
				}
			}
			
		
		
		
        	$template->param( indentation_list => \@idd_list);
       	 $self->output_html($template->output());
         }
}



sub configure {
    my ( $self, $args ) = @_;

    my $cgi = $self->{'cgi'};
}

sub install() {
    my ( $self, $args ) = @_;
    my $indentation_table = "indentation_list_table";
    return 1;

}

sub uninstall() {
    my ( $self, $args ) = @_;
    my $table = "indentation_list_table";

    return 1;
}
