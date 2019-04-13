#!/usr/bin/perl

use 5.010;
use warnings;
use strict;
use utf8;
use Carp;
use Encode qw(encode decode);

use FindBin;
use lib "$FindBin::Bin/";

use File::Slurp qw(read_file write_file);
use Digest::MD5 qw(md5_hex);

use AG::Config;
use AG::Categories;

use TeX::Processor::Parser;
use TeX::Processor::Printer;
use TeX::Processor::Make;
use TeX::Processor;

no if $] >= 5.018, warnings => "experimental::smartmatch";

sub msg {
    my $caller = ( caller 1 )[3] // '[no_caller]';

    print "$caller(): @_\n";
    return;
}

{
    my $images_dpi = 200;

    sub pdf_of_png {
        my $global = shift;
        my $svg    = shift;

        my $q_dpi   = quotemeta $images_dpi;
        my $q_svg   = quotemeta $svg;
        my $command = "inkscape -D -d $q_dpi -z $q_svg -e ";
        my $png     = "$global->{config}{destination_directory}/" . ( md5_hex $command) . ".png";
        if ( ! -e $png || ( stat $png )[9] < ( stat $svg )[9] ) {
            system $command . quotemeta $png;
        }

        return $png;
    }
}

binmode STDOUT, ':encoding(utf-8)';

my $global = AG::Config::init();

if ( ! -e $global->{config}{destination_directory} && ! mkdir $global->{config}{destination_directory} ) {
    croak "Cannot create destination direcotry: $!";
}

my %commands_map;

my @tex_route_lists;
while ( my ( $lname, $list ) = each %{ $global->{config}{lists} } ) {
    my @list_routes = grep {
        ( $list->{routes_filter} // sub {1} )->($_)
    } @{ $global->{routes} };

    my $route_template = decode( 'utf-8', read_file("$global->{config}{template_directory}/$list->{route_template}") );

    my $content = q{};
    foreach my $route (@list_routes) {
        my $description = decode( 'utf-8', read_file("$route->{path}/description.tex") );
        $description = TeX::Processor::Parser::parse( id => "$route->{path}/description.tex", document => $description );

        my $category = AG::Categories::get( $global, $route->{category} );
        my $peaks = join q{, }, @{ $route->{peak} };

        my $uiaa = q{};
        if ( -f "$route->{path}/uiaa.svg" ) {
            $uiaa = pdf_of_png( $global, "$route->{path}/uiaa.svg" );
        }

        my $region = $global->{regions}{ $route->{region} };

        my $geopoints_mapper = sub {
            my $command = shift;

            if ( my ($geoname) = $command->{command} =~ m{^geo(.+)} ) {
                if ( exists $region->{geopoints}{$geoname} ) {
                    my $point = $region->{geopoints}{$geoname};
                    my $name  = $point->{name};
                    if ( defined $command->{args} && @{ $command->{args} } && @{ $command->{args}[0]{content} } ) {
                        $name = TeX::Processor::Printer::latex( document => $command->{args}[0]{content} );
                    }
                    return 1,
                        TeX::Processor::Make::command(
                        command => 'geopoint',
                        args    => [
                            { type => 'brace', content => [ TeX::Processor::Make::text( sprintf '%.7f', $point->{latitude} ) ], },
                            { type => 'brace', content => [ TeX::Processor::Make::text( sprintf '%.7f', $point->{longtitude} ) ], },
                            { type => 'brace', content => [ TeX::Processor::Make::text( $point->{altitude} // q{} ) ], },
                            { type => 'brace', content => [ TeX::Processor::Make::text($name) ], },
                            { type => 'brace', content => [ TeX::Processor::Make::text($point->{name}) ], },
                        ] );
                }
            }

            return 0;
        };

        my $mapper = sub {
            my $doc = shift;

            return TeX::Processor::map_commands(
                list => $doc,
                map  => {
                    routeTitle       => sub { TeX::Processor::Make::text( $route->{title} ) },
                    routePeak        => sub { TeX::Processor::Make::text($peaks) },
                    routeCategory    => sub { TeX::Processor::Make::text($category) },
                    routeType        => sub { TeX::Processor::Make::text( $route->{type} ) },
                    routeName        => sub { TeX::Processor::Make::text( $route->{name} ) },
                    routeRegionName  => sub { TeX::Processor::Make::text( $region->{name} ) },
                    routeEquipment   => sub { TeX::Processor::Make::text( $route->{equipment} ) },
                    routeAuthors     => sub { TeX::Processor::Make::text( join q{, }, sort @{ $route->{authors} } ) },
                    routeDescription => sub { TeX::Processor::Make::text($description) },
                    routeUIAAPath    => sub { TeX::Processor::Make::text($uiaa) },
                },
                unified => $geopoints_mapper
            );
        };

        $description = $mapper->($description);
        $description = TeX::Processor::Printer::latex( document => $description );

        my $doc = $route_template;

        $doc = TeX::Processor::Parser::parse( id => "List $lname, route '$route->{title}'", document => $doc );
        $doc = $mapper->($doc);

        $content .= TeX::Processor::Printer::latex( document => $doc );
    }

    my $doc = TeX::Processor::Parser::parse( id => "List $lname", document => $content, error_context => 1000 );
    $commands_map{$lname} = sub { return @{$doc} };
    push @tex_route_lists, "\\newcommand{\\routeList$lname}[0]{$content}\n";
}

my $book = read_file( "$global->{config}{template_directory}/book.tex", binmode => ':utf8' );
$book = TeX::Processor::Parser::parse( document => $book );
$book = TeX::Processor::map_commands(
    list => $book,
    map  => \%commands_map
);

system "cd " . ( quotemeta $global->{config}{destination_directory} ) . "; rm -f book.*";

write_file( "$global->{config}{destination_directory}/book.tex", encode( 'utf-8', TeX::Processor::Printer::latex( document => $book ) ) );

system "cd "
    . ( quotemeta $global->{config}{destination_directory} )
    . "; makeglossaries book.glo; pdflatex -halt-on-error -file-line-error book.tex && pdflatex -halt-on-error -file-line-error book.tex";
