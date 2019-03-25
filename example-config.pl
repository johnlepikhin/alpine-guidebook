{   destination_directory => '/tmp/guidebook',
    category_system       => 'russian',
    template_directory    => 'templates/template1',
    lists => {
             EasyAlaArcha => {
                               routes_filter  => sub {
                                   $_->{region} eq 'ala-archa' && $_->{category} le '3Б'
                               },
                               route_template => 'route-template1.tex',
                              },
             MiddleAlaArcha => {
                               routes_filter  => sub {
                                   $_->{region} eq 'ala-archa' && $_->{category} gt '3Б' && $_->{category} lt '5Б'
                               },
                               route_template => 'route-template1.tex',
                              },
            }
}
