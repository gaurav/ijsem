#!/usr/bin/perl -w

use v5.10;
use strict;
use warnings;

use URI;
use Try::Tiny;
use Getopt::Long;
use LWP::UserAgent;
use File::Temp;
use Pod::Usage;
use HTML::TreeBuilder::XPath;
use Data::Dumper;
use HTML::TableExtract;

# Command line options? We expect a URL to either:
#   1. A journal issue to extract data from.
#   2. The article containing the nomenclatural changes.
#   3. The table to extract data from.
my $help =  0;
my $man =   0;

my $VOLUMES_PATH = "data/ijsem_extract";
my $url = "http://ijs.sgmjournals.org/content/current";
my $result = GetOptions(
    "url=s" =>      \$url,
    "help|?" =>     \$help,
    "man" =>        \$man
) or pod2usage(2);
pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

# Check if there is a single ARGV variable; if so, it's the URL.
if(exists($ARGV[0]) and not exists($ARGV[1])) {
    $url = $ARGV[0];
}

# Okay, go time!
process($url);

sub process {
    my $url = shift;

    say "Downloading content from $url ...";
    my $content = download_page($url);

    # What is it, then?
    given($content) {
        when(/<title>Table of Contents/) {
            # Find the Notification List.
            my $tree =  HTML::TreeBuilder::XPath->new;
            say "Parsing with HTML::TreeBuilder::XPath.";
            $tree->parse(lc $content);
            my $notification_list = $tree->findnodes('//div[./h2[@id="notificationlist"]]')->[0];
            if (not defined $notification_list) {
                say "Unable to find notification list!"; 
                save_content_and_bail($content);
            }
            my $relative_url = $notification_list->findvalue('.//a[@rel="full-text"]/@href');
            $tree->delete();

            # Note that since IJSEM 62(2) $relative_url needs
            # the 'pt_' capitalized (we lowercase it earlier to make
            # it easier to spot.
            $relative_url =~ s/pt_/Pt_/g;

            my $uri = URI->new($url);
            $uri->path($relative_url);

            say "Switching to notification list at $uri.";
            process($uri);
        }

        when(/<title>Notification that new names and new combinations have appeared in volume (\d+), part (\d+), of the IJSEM/) {
            my $volume =    $1;
            my $part =      $2;
            say "Content identified as notification of new names and combinations in volume $volume, part $part.";

            if($content =~ /<div class="callout"><span>View this table:<\/span><ul class="callout-links">/) {
                say "Content identified as article page. Jumping to table 1.";
                $url =~ s/\/(\d+).full/\/$1\/T1.expansion.html/g;
                process($url);
            } else {
                process_notification_table($volume, $part, $content);
            }
        }
        default {
            say "Sorry, unable to identify content at $url.";

            save_content_and_bail($content);
        }
    }
}

# Process notification tables.
sub process_notification_table {
    my ($vol, $part, $content) = @_;

    mkdir "$VOLUMES_PATH/volume_$vol";
    open my $fh, ">:utf8", "$VOLUMES_PATH/volume_$vol/part_$part.txt";
    say $fh "From [$url] Volume [$vol] Part [$part]";

    my $te = HTML::TableExtract->new( 
        # headers => ["Name/author(s):", "Proposed as:", "Page no."]
        attribs => { id => 'table-1' }
    );
    $te->parse($content);

    my $count_names = 0;
    foreach my $table ($te->tables()) {
        my @rows = $te->rows();
        shift @rows;    # Get rid of the first row: the title row.

        say $fh "# " . scalar(@rows) . " rows detected.";

        foreach my $row (@rows) {
            my $name =          $row->[0];
            my $proposed_as =   $row->[1];
            my $page_no =       $row->[2];

            $name =~ s/\s*$//g;

            if($proposed_as eq 'emend.*') {
                $proposed_as = 'emend (taxonomic opinion)';
            }

            my $string = "\@$page_no [$proposed_as] \"$name\"";

            say $fh $string;
            # say $string;
            $count_names++;
        }
    }

    close $fh;
    say "$count_names names downloaded.";
}

# Download a page.
sub download_page {
    my $url = shift;
    my $lwp = LWP::UserAgent->new();

    my $response = $lwp->get($url);
    my $content = $response->decoded_content;

    unless($response->is_success()) {
        die "Error connecting to $url: " . Dumper($response);
    }

    return $content;
}

sub save_content_and_bail {
    my $content = shift;

    my $tmp = File::Temp->new(UNLINK => 0);
    binmode $tmp, ":utf8";
    say $tmp $content;
    close $tmp;

    say "Website content was stored in file '" . $tmp->filename . "' for perusal.";
    exit(1);
}

