package HTML::FormHandler;

use Moose;
use MooseX::AttributeHelpers;
extends 'HTML::FormHandler::Model';
with 'HTML::FormHandler::Fields';
with 'HTML::FormHandler::TransformAndCheck';

use Carp;
use Locale::Maketext;
use HTML::FormHandler::I18N; 
use HTML::FormHandler::Params;

use 5.008;

our $VERSION = '0.24';

=head1 NAME

HTML::FormHandler - form handler written in Moose 

=head1 SYNOPSIS

An example of a form class:

    package MyApp::Form::User;
    
    use HTML::FormHandler::Moose;
    extends 'HTML::FormHandler::Model::DBIC';

    has '+item_class' => ( default => 'User' );

    has_field 'name' => ( type => 'Text' );
    has_field 'age' => ( type => 'PosInteger', apply => [ 'MinimumAge' ] );
    has_field 'birthdate' => ( type => 'DateTime' );
    has_field 'hobbies' => ( type => 'Multiple' );
    has_field 'address' => ( type => 'Text' );
    has_field 'city' => ( type => 'Text' );
    has_field 'state' => ( type => 'Select' );
    has_field 'email' => ( type => 'Email' );

    has '+dependency' => ( default => sub {
          [ ['address', 'city', 'state'], ]
       }
    );

    subtype 'MinimumAge'
       => as 'Int'
       => where { $_ > 13 }
       => message { "You are not old enough to register" };
    
    no HTML::FormHandler::Moose;
    1;


An example of a Catalyst controller that uses an HTML::FormHandler form
to update a 'Book' record:

   package MyApp::Controller::Book;
   BEGIN {
      use Moose;
      extends 'Catalyst::Controller';
   }
   use MyApp::Form::Book;
   has 'edit_form' => ( isa => 'MyApp::Form::Book', is => 'rw',
       lazy => 1, default => sub { MyApp::Form::Book->new } );

   sub book_base : Chained PathPart('book') CaptureArgs(0)
   {
      my ( $self, $c ) = @_;
      # setup
   }
   sub item : Chained('book_base') PathPart('') CaptureArgs(1)
   {
      my ( $self, $c, $book_id ) = @_;
      $c->stash( book => $c->model('DB::Book')->find($book_id) );
   }
   sub edit : Chained('item') PathPart('edit') Args(0)
   {
      my ( $self, $c ) = @_;

      $c->stash( form => $self->edit_form, template => 'book/form.tt' );
      return unless $self->edit_form->process( item => $c->stash->{book},
         params => $c->req->parameters );
      $c->res->redirect( $c->uri_for('list') );
   }

The example above creates the form as a persistent part of the application
with the Moose <C has 'edit_form' > declaration.
If you prefer, it also works fine to create the form on each request:
    
    my $form = MyApp::Form->new;
    $form->process( item => $book, params => $params );

or, for a non-database form:

    my $form = MyApp::Form->new;
    $form->process( $params );
   
A dynamic form may be created in a controller using the field_list
attribute to set fields:

    my $form = HTML::FormHandler->new(
        item => $user,
        field_list => [
               first_name => 'Text',
               last_name => 'Text' 
        ],
    );


=head1 DESCRIPTION

HTML::FormHandler allows you to define HTML form fields and validators. It can
be used for both database and non-database forms, and will
automatically update or create rows in a database.

One of its goals is to keep the controller interface as simple as possible,
and to minimize the duplication of code. In most cases, interfacing your
controller to your form is only a few lines of code.

With FormHandler you'll never spend hours trying to figure out how to make a 
simple HTML change that would take one minute by hand. Because you CAN do it
by hand. Or you can automate HTML generation as much as you want, with
template widgets or pure Perl rendering classes, and stay completely in
control of what, where, and how much is done automatically. 

You can split the pieces of your forms up into logical parts and compose
complete forms from FormHandler classes, roles, fields, collections of
validations, transformations and Moose type constraints. 
You can write custom methods to 
process forms, add any attribute you like, use Moose before/after/around. 
FormHandler forms are Perl classes, so there's a lot of flexibility in what 
you can do. See L<HTML::FormHandler::Field/apply> for more info.

The L<HTML::FormHandler> module is documented here.  For more extensive 
documentation on use and a tutorial, see the manual at 
L<HTML::FormHandler::Manual>.

HTML::FormHandler does not provide a complex HTML generating facility,
but a simple, sample rendering role is provided by 
L<HTML::FormHandler::Render::Simple>, which will output HTML formatted
strings for a field or a form. There are also sample Template Toolkit
widget files in the example, documented at 
L<HTML::FormHandler::Manual::Templates>.

The typical application for FormHandler would be in a Catalyst, DBIx::Class, 
Template Toolkit web application, but use is not limited to that.


=head1 ATTRIBUTES and METHODS

=head2 Creating a form with 'new' 

The new constructor takes name/value pairs:

    MyForm->new(
        item    => $item,
        init_object => { name => 'Your name here', username => 'choose' }
    );

No attributes are required on new for a non-database form.
The common attributes to be passed in to the constructor for a database form 
are either item_id and schema or item:

   item_id  - database row primary key
   item     - database row object
   schema   - (for DBIC) the DBIx::Class schema

The following are occasionally passed in, but are more often set
in the form class:

   item_class  - source name of row
   dependency  - (see dependency)
   field_list  - and array of field definitions
   init_object - a hashref or object to provide initial values

Examples of creating a form object with new:

    # non-database form
    my $form = MyApp::Form::User->new;
    # database form using a row object
    my $form = MyApp::Form::Member->new( item => $row );
    # a dynamic form (no form class has been defined) 
    my $form = HTML::FormHandler::Model::DBIC->new(
        item_id         => $id,
        item_class    => 'User', 
        schema          => $schema,
        field_list         => [
                name    => 'Text',
                active  => 'Boolean',
        ],
    );

The 'item', 'item_id', and 'item_class' attributes are defined
in L<HTML::FormHandler::Model>, and 'schema' is defined in
L<HTML::FormHandler::Model::DBIC>.

FormHandler forms are handled in two steps: 1) create with 'new',
2) handle with 'process'. FormHandler doesn't
care whether most parameters are set on new or process or update,
but a 'field_list' argument must be passed in on 'new'.

=head2 Processing the form

=head3 process

Call the 'process' method on your form to perform validation and 
update. A database form must have either an item (row object) or
a schema, item_id (row primary key), and item_class (usually set in the form).

   $form->process( item => $book, params => $c->req->parameters );

or:

   $form->process( item_id => $item_id,
       schema => $schema, params => $c->req->parameters );

This method returns the 'validated' flag. (C<< $form->validated >>)
If it is a database form and the form validates, the database row
will be updated.

If it is not a database form, you can get HTTP parameter type values
from C<< $form->fif >> or a hash of inflated values from C<< $form->values >>.

=head3 params

Parameters must be passed in or set before you call 'process'. 
HFH gets data to validate and store in the database from the params hash. 

Params can either be in the form of CGI/HTTP style params:

   {
      user_name => "Joe Smith",
      occupation => "Programmer",
      'addresses.0.street' => "999 Main Street",
      'addresses.0.city' => "Podunk",
      'addresses.0.country' => "UT",
      'addresses.0.address_id' => "1",
      'addresses.1.street' => "333 Valencia Street",
      'addresses.1.city' => "San Franciso",
      'addresses.1.country' => "UT",
      'addresses.1.address_id' => "2",
   }

or as structured data in the form of hashes and lists:

   {
      addresses => [
         {
            city => 'Middle City',
            country => 'GK',
            address_id => 1,
            street => '101 Main St',
         },
         {
            city => 'DownTown',
            country => 'UT',
            address_id => 2,
            street => '99 Elm St',
         },
      ],
      'occupation' => 'management',
      'user_name' => 'jdoe',
   }

CGI style parameters will be converted to hashes and lists for HFH to
operate on.

The parameters are stored in a 'params' attribute.
Also: set_param, get_param, clear_params, delete_param, 
has_params from Moose 'Collection::Hash' metaclass. 

You can add an additional param when setting them:

   $form->process( params => { %{$c->req->params}, new_param  => 'something' } );

=head2 Getting data out

=head3 fif  (fill in form)

Returns a hash of values suitable for use with HTML::FillInForm
or for filling in a form with C<< $form->fif->{fieldname} >>.
The fif value for a 'title' field in a TT form:

   [% form.fif.title %] 

Or you can use the 'fif' method on individual fields:

   [% form.field('title').fif %]

=head3 values

Returns a hashref of all field values. Useful for non-database forms.
The 'fif' and 'values' hashrefs might be the same for simple forms unless there's a
difference in format between the HTML field values (in fif) and the saved value
or unless the field 'name' and 'accessor' are different. 'fif' returns
a hash with the field names for the keys and the field's 'fif' for the
values; 'values' returns a hash with the field accessors for the keys, and the
field's 'value' for the the values. 

Forms containing arrays to be processed with L<HTML::FormHandler::Field::Repeatable>
will have parameters with dots and numbers, like 'addresses.0.city', while the
values hash will transform the fields with numbers to arrays.

=head2 Accessing and setting up fields

Fields are declared with a number of attributes which are defined in
L<HTML::FormHandler::Field>. If you want additional attributes you can
define your own field classes. The field 'type' is the short class name
of the field class.

=head3 has_field

The most common way of declaring fields is the 'has_field' syntax.
Using the 'has_field' syntax sugar requires C< use HTML::FormHandler::Moose; >.
See L<HTML::FormHandler::Manual::Intro>

   use HTML::FormHandler::Moose;
   has_field 'field_name' => ( type => 'FieldClass', .... );

=head3 field_list

A 'field_list' is an array of field definitions which can be used as an
alternative to 'has_field' in small, dynamic forms.

    field_list => [
       field_one => {
          type => 'Text',
          required => 1
       },
       field_two => 'Text,
    ]


=head3 field_name_space

Use to set the name space used to locate fields that 
start with a "+", as: "+MetaText". Fields without a "+" are loaded
from the "HTML::FormHandler::Field" name space. If 'field_name_space'
is not set, then field types with a "+" must be the complete package
name.

=head3 fields

The array of fields, objects of L<HTML::FormHandler::Field> or its subclasses.
A compound field will itself have an array of fields,
so this is a tree structure.

=head3 field($name)

This is the method that is usually called to access a field:

    my $title = $form->field('title')->value;
    [% f = form.field('title') %]

    my $city = $form->field('addresses.0.city')->value;

Pass a second true value to die on errors.
 
=head2 Constraints and validation

Most validation in performed on a per-field basis, and there are a number
of different places in which validation can be performed. 

=head3 Apply actions

The 'actions' array contains a sequence of transformations, constraints
(including Moose type constraints) which will be applied in order. The 
current value of the field is passed in to the subroutines, but it has 
no access to other field information. 
This is probably the best place to 
put constraints and transforms if all that is needed is the current value.
The L<HTML::FormHandler::Field::Compound> fields receive as value 
a hash containing values of their child fields - this may be used for
easy creation of objects (like DateTime).
See L<HTML::FormHandler::Field/apply> for more documentation.

   has_field 'test' => ( apply => [ 'MyConstraint', 
                         { check => sub {... },
                           message => '....' },
                         { transform => sub { ... },
                           message => '....' }
                         ] );

=head3 Field class validate method

The 'validate' method can be used in field classes to perform additional validation.
It has access to the field ($self).  This method is called after the actions are performed.

=head3 Form class validation for individual fields

You can define a method in your form class to perform validation on a field. 
This method is the equivalent of the field class validate method except it is
in the form class, so you might use this validation method if you don't
want to create a field subclass. 

It has access to the form ($self) and the field.
This method is called after the field class 'validate' method. The name of 
this method can be set with 'set_validate' on the field. The default is 
'validate_' plus the field name:

   sub validate_testfield { my ( $self, $field ) = @_; ... }

If the field name has dots they should be replaced with underscores.

=head3 validate

(This method used to be called 'cross_validate'. It was renamed to 'validate'
to make the api more consistent.)
This is a form method that is useful for cross checking values after they have
been saved as their final validated value, and for performing more complex 
dependency validation. It is called after all other field validation is done, 
and whether or not validation has succeeded, so it has access to the 
post-validation values of all the fields.

=head2 Accessing errors 

  has_errors - returns true or false
  error_fields - returns list of fields with errors
  errors - returns array of error messages for the entire form
  num_errors - number of errors in form

=head2 Clear form state

Various clear methods are used in internal processing, and might be
useful in some situations.

   clear - clears state, params, ctx
   clear_state - clears flags, errors, fif, values, input 
   clear_values, clear_errors, clear_fif - on all fields

=head2 Miscellaneous attributes

=head3 name

The form's name.  Useful for multiple forms.
It used to construct the default 'id' for fields, and is used
for the HTML field name when 'html_prefix' is set. 
The default is "form" + a one to three digit random number.

=head3 init_object

If an 'init_object' is supplied on form creation, it will be used instead 
of the 'item' to pre-populate the values in the form. This can be useful 
when populating a form from default values stored in a similar but different 
object than the one the form is creating. The 'init_object' should be either
a hash or the same type of object that the model uses (a DBIx::Class row for
the DBIC model).

=head3 ctx

Place to store application context

=head3 language_handle, build_language_handle

Holds a Local::Maketext language handle

The builder for this attribute gets the Locale::Maketext language 
handle from the environment variable $ENV{LANGUAGE_HANDLE}, or creates 
a default language handler using L<HTML::FormHandler::I18N>. The
language handle is used in the field's add_error method to allow
localizing.

=head3 dependency

Arrayref of arrayrefs of fields. If one of a group of fields has a
value, then all of the group are set to 'required'.

  has '+dependency' => ( default => sub { [
     ['street', 'city', 'state', 'zip' ],] }
  );

=head2 Flags

=head3 validated

Flag that indicates if form has been validated. You might want to use 
this flag if you're doing something in between process and returning, 
such as setting a stash key.

   $form->process( ... );
   $c->stash->{...} = ...;
   return unless $form->validated;

=head3 ran_validation

Flag to indicate that validation has been run. This flag will be
false when the form is initially loaded and displayed, since
validation is not run until FormHandler has params to validate.

=head3 verbose

Flag to dump diagnostic information. See 'dump_fields' and
'dump_validated'.

=head3 html_prefix

Flag to indicate that the form name is used as a prefix for fields
in an HTML form. Useful for multiple forms
on the same HTML page. The prefix is stripped off of the fields
before creating the internal field name, and added back in when
returning a parameter hash from the 'fif' method. For example,
the field name in the HTML form could be "book.borrower", and
the field name in the FormHandler form (and the database column)
would be just "borrower".

   has '+name' => ( default => 'book' );
   has '+html_prefix' => ( default => 1 );

Also see the Field attribute "html_name", a convenience function which
will return the form name + "." + field full_name

=head2 For use in HTML
 
   http_method - For storing 'post' or 'get'
   action - Store the form 'action' on submission. No default value.
   enctype - Request enctype
   submit - Store form submit field info. No default value.
   uuid - generates a string containing an HTML field with UUID


=cut

# Moose attributes
has 'name' => (
   isa     => 'Str',
   is      => 'rw',
   default => sub { return 'form' . int( rand 1000 ) }
);
# for consistency in api with field nodes
has 'form' => ( isa => 'HTML::FormHandler', is => 'rw', weak_ref => 1,
   lazy => 1, default => sub { shift });
has 'parent' => ( is => 'rw' );
# object with which to initialize
has 'init_object' => ( is => 'rw', clearer => 'clear_init_object' );
# flags
has [ 'ran_validation', 'validated', 'verbose', 'processed', 'did_init_obj' ] => 
    ( isa => 'Bool', is => 'rw' );
has 'user_data' => ( isa => 'HashRef', is => 'rw' );
has 'ctx' => ( is => 'rw', weak_ref => 1, clearer => 'clear_ctx' );
# for Locale::MakeText
has 'language_handle' => (
   is      => 'rw',
   builder => 'build_language_handle'
);
has 'num_errors' => ( isa => 'Int', is => 'rw', default => 0 );
has 'html_prefix' => ( isa => 'Bool', is => 'rw' );
has 'active_column' => ( isa => 'Str', is => 'rw' );
has 'http_method' => ( isa => 'Str', is => 'rw', default => 'post' );
has 'enctype' => (is => 'rw', isa => 'Str', default => 'application/x-www-form-urlencoded');
has 'action' => ( is => 'rw' );
has 'submit' => ( is => 'rw' );
has 'params' => (
   metaclass  => 'Collection::Hash',
   isa        => 'HashRef',
   is         => 'rw',
   default    => sub { {} },
   auto_deref => 1,
   trigger    => sub { shift->_munge_params(@_) },
   provides   => {
      set    => 'set_param',
      get    => 'get_param',
      clear  => 'clear_params',
      delete => 'delete_param',
      empty  => 'has_params',
   },
);
has 'dependency' => ( isa => 'ArrayRef', is => 'rw' );
has '_required' => (
   metaclass  => 'Collection::Array',
   isa        => 'ArrayRef[HTML::FormHandler::Field]',
   is         => 'rw',
   default    => sub { [] },
   auto_deref => 1,
   provides   => {
      clear => 'clear_required',
      push  => 'add_required'
   }
);

sub BUILDARGS
{
   my $class = shift;

   if ( @_ == 1 )
   {
      my $id = $_[0];
      return { item => $id, item_id => $id->id } if (blessed $id);
      return { item_id => $id };
   }
   return $class->SUPER::BUILDARGS(@_); 
}

sub BUILD
{
   my $self = shift;

   $self->_build_fields;    # create the form fields
   return if defined $self->item_id && !$self->item;
   # load values from object (if any)
   if( $self->init_object || $self->item )
   {
      $self->_init_from_object( $self, $self->init_object || $self->item );
   }
   else
   {
      $self->_init;
   }
   $self->dump_fields if $self->verbose;
   return;
}

sub build_language_handle
{
   my $lh = $ENV{LANGUAGE_HANDLE}
      || HTML::FormHandler::I18N->get_handle
      || die "Failed call to Locale::Maketext->get_handle";
   return $lh;
}

# deprecated
sub update
{
   warn "HFH update method is deprecated. Please switch to using 'process'.";
   shift->process(@_);
}
 
sub process
{
   my ( $self, @args ) = @_;

   warn "HFH: process ", $self->name, "\n" if $self->verbose;
   $self->clear if $self->processed;
   $self->_setup_form(@args);
   $self->validate_form if $self->has_params;
   $self->update_model if $self->validated;
   $self->dump_fields if $self->verbose;
   $self->processed(1);
   return $self->validated;
}

sub db_validate
{
   my $self = shift;
   my $fif = $self->fif;
   $self->process( $fif );
   return $self->validated;
}

sub clear
{ 
   my $self = shift;
   warn "HFH: clear ", $self->name, "\n" if $self->verbose;
   $self->clear_state;
   $self->clear_params;
   $self->clear_ctx;
   $self->processed(0);
   $self->did_init_obj(0);
}

sub clear_state
{
   my $self = shift;
   $self->validated(0);
   $self->ran_validation(0);
   $self->num_errors(0);
   $self->clear_data;
}

sub clear_data
{
   shift->clear_value;
}

sub clear_fif { shift->clear_fifs }

sub fif
{
   my ( $self, $prefix, $node ) = @_;

   if ( !defined $node )
   {
      $node   = $self;
      $prefix = '';
      $prefix = $self->name . "." if $self->html_prefix;
   }
   my %params;
   foreach my $field ( $node->fields )
   {
      next if $field->password;
      my $fif = $field->fif;    # need to force lazy build
      next unless $field->has_fif && defined $fif;
      if ( $field->DOES('HTML::FormHandler::Fields') )
      {
         my $next_params = $self->fif( $prefix . $field->name . '.', $field );
         next unless $next_params;
         %params = ( %params, %{$next_params} );
      }
      else
      {
         $params{ $prefix . $field->name } = $fif;
      }
   }
   return if !%params;
   return \%params;
}

sub values { shift->value }

# deprecated
sub has_error
{
   my $self = shift;
   return $self->ran_validation && !$self->validated;
}

sub has_errors
{
   for ( shift->fields )
   {
      return 1 if $_->has_errors;
   }
   return 0;
}

sub error_fields
{
   return grep { $_->has_errors } shift->sorted_fields;
}

# deprecated?
sub error_field_names
{
   my $self         = shift;
   my @error_fields = $self->error_fields;
   return map { $_->name } @error_fields;
}

sub errors
{
   my $self         = shift;
   my @error_fields = $self->error_fields;
   return map { $_->errors } @error_fields;
}

sub uuid
{
   my $form = shift;
   require Data::UUID;
   my $uuid = Data::UUID->new->create_str;
   return qq[<input type="hidden" name="form_uuid" value="$uuid">];
}

sub validate_form
{
   my $self = shift;
   my $params = $self->params; 
   $self->_set_dependency;    # set required dependencies
   $self->input( $params );
   $self->build_node;
   $self->_apply_actions;
   $self->validate();
   # model specific validation 
   $self->validate_model;
   $self->_clear_dependency;

   # count errors 
   my $errors;
   for ( $self->fields )
   {
      $errors++ if $_->has_errors;
   }
   $self->num_errors( $errors || 0 );
   $self->ran_validation(1);
   $self->validated( !$errors );
   $self->dump_validated if $self->verbose;

   return $self->validated;
}

sub cross_validate { shift->validate(@_) }

sub _setup_form
{
   my ($self, @args) = @_;
   if( @args == 1 )
   {
      $self->params( $args[0] );
   }
   elsif ( @args > 1 )
   {
      my $hashref = {@args};
      while ( my ($key, $value) = each %{$hashref} )
      {
         $self->$key($value) if $self->can($key);
      } 
   }
   if( $self->item_id && !$self->item )
   {
      $self->item( $self->build_item);
   }
   # initialization of Repeatable fields and Select options
   # will be done in init_object when there's an initial object
   # in validation routines when there are params
   # and by _init for empty forms
   if( ($self->init_object || $self->item) && !$self->did_init_obj )
   {
      $self->_init_from_object( $self, $self->init_object || $self->item );
   }
   if ( !$self->has_params && !$self->did_init_obj )
   {
      # no initial object. empty form form must be initialized
      $self->_init;
   }
}

sub _init_from_object
{
   my ( $self, $node, $item ) = @_;

   $node ||= $self;
   return unless $item; 
   warn "HFH: init_from_object ", $self->name, "\n" if $self->verbose;
   my $my_value;
   for my $field ( $node->fields )
   {
      next if $field->parent && $field->parent != $node;
      next if $field->writeonly;
      next if ref $item eq 'HASH' && !exists $item->{ $field->accessor };
      my $value = $self->_get_value( $field, $item );
      #      $value = $field->_apply_deflations( $value );
      if ( $field->isa('HTML::FormHandler::Field::Repeatable') )
      {
         $field->_init_from_object( $value );
      }
      elsif ( $field->isa('HTML::FormHandler::Field::Compound') )
      {
         $self->_init_from_object( $field, $value );
         $field->value($value);
      }
      else
      {
         if ( $field->_can_init_value )
         {
            my @values;
            @values = $field->_init_value( $field, $item );
            my $value = @values > 1 ? \@values : shift @values;
            $field->init_value($value) if $value;
            $field->value($value)      if $value;
         }
         else
         {
            $self->init_value( $field, $value );
         }
         $field->_load_options if $field->can('_load_options');
      }
      $my_value->{$field->name} = $field->value;
   }
   $self->value( $my_value );
   $self->did_init_obj(1);
}

sub _get_value
{
   my ( $self, $field, $item ) = @_;
   my $accessor = $field->accessor;
   my @values;
   if ( blessed($item) && $item->can($accessor))
   {
      @values = $item->$accessor;
   }
   elsif ( exists $item->{$accessor} )
   {
      @values = $item->{$accessor};
   }
   else
   {
      return;
   }
   my $value = @values > 1 ? \@values : shift @values;
   return $value;
}

sub init_value
{
   my ( $self, $field, $value ) = @_;
   $field->init_value($value);
   $field->value($value);
}

sub _set_dependency
{
   my $self = shift;

   my $depends = $self->dependency || return;
   my $params = $self->params;
   for my $group (@$depends)
   {
      next if @$group < 2;
      # process a group of fields
      for my $name (@$group)
      {
         # is there a value?
         my $value = $params->{$name};
         next unless defined $value;
         # The exception is a boolean can be zero which we count as not set.
         # This is to allow requiring a field when a boolean is true.
         my $field = $self->field($name);
         next if $self->field($name)->type eq 'Boolean' && $value == 0;
         if ( ref $value )
         {
            # at least one value is non-blank
            next unless grep { /\S/ } @$value;
         }
         else
         {
            next unless $value =~ /\S/;
         }
         # one field was found non-blank, so set all to required
         for (@$group)
         {
            my $field = $self->field($_);
            next unless $field && !$field->required;
            $self->add_required($field);        # save for clearing later.
            $field->required(1);
         }
         last;
      }
   }
}

sub _clear_dependency
{
   my $self = shift;

   $_->required(0) for $self->_required;
   $self->clear_required;
}

sub _munge_params
{
   my ( $self, $params, $attr ) = @_;
   my $_fix_params = HTML::FormHandler::Params->new;
   my $new_params = $_fix_params->expand_hash($params);
   if ( $self->html_prefix )
   {
      $new_params = $new_params->{$self->name};
   }
   my $final_params = {%{$params}, %{$new_params}};
   $self->{params} = $final_params;
}

=head1 SUPPORT

IRC:

  Join #formhandler on irc.perl.org

Mailing list:

  http://groups.google.com/group/formhandler

Code repository:

  http://github.com/gshank/html-formhandler/tree/master

=head1 SEE ALSO

L<HTML::FormHandler::Manual>

L<HTML::FormHandler::Manual::Tutorial>

L<HTML::FormHandler::Manual::Intro>

L<HTML::FormHandler::Manual::Templates>

L<HTML::FormHandler::Manual::Cookbook>

L<HTML::FormHandler::Field>

L<HTML::FormHandler::Model::DBIC>

L<HTML::FormHandler::Moose>


=head1 CONTRIBUTORS

gshank: Gerda Shank <gshank@cpan.org>
zby:    Zbigniew Lukasiak <zby@cpan.org>

Based on the source code of L<Form::Processor> by Bill Moseley

=head1 COPYRIGHT

This library is free software, you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

HTML::FormHandler->meta->make_immutable;
no Moose;
1;
