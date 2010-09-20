# BEGIN BPS TAGGED BLOCK {{{
#
# COPYRIGHT:
#
# This software is Copyright (c) 1996-2010 Best Practical Solutions, LLC
#                                          <jesse@bestpractical.com>
#
# (Except where explicitly superseded by other copyright notices)
#
#
# LICENSE:
#
# This work is made available to you under the terms of Version 2 of
# the GNU General Public License. A copy of that license should have
# been provided with this software, but in any event can be snarfed
# from www.gnu.org.
#
# This work is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301 or visit their web page on the internet at
# http://www.gnu.org/licenses/old-licenses/gpl-2.0.html.
#
#
# CONTRIBUTION SUBMISSION POLICY:
#
# (The following paragraph is not intended to limit the rights granted
# to you to modify and distribute this software under the terms of
# the GNU General Public License and is only of importance to you if
# you choose to contribute your changes and enhancements to the
# community by submitting them to Best Practical Solutions, LLC.)
#
# By intentionally submitting any modifications, corrections or
# derivatives to this work, or any other work intended for use with
# Request Tracker, to Best Practical Solutions, LLC, you confirm that
# you are the copyright holder for those contributions and you grant
# Best Practical Solutions,  LLC a nonexclusive, worldwide, irrevocable,
# royalty-free, perpetual, license to use, copy, create derivative
# works based on those contributions, and sublicense and distribute
# those contributions and any derivatives thereof.
#
# END BPS TAGGED BLOCK }}}

=head1 SYNOPSIS

  use RT::ACE;
  my $ace = RT::ACE->new($CurrentUser);


=head1 DESCRIPTION



=head1 METHODS


=cut


package RT::ACE;

use strict;
no warnings qw(redefine);
use RT::Principals;
use RT::Queues;
use RT::Groups;

use vars qw (
  %LOWERCASERIGHTNAMES
  %OBJECT_TYPES
  %TICKET_METAPRINCIPALS
);



=head1 Rights

# Queue rights are the sort of queue rights that can only be granted
# to real people or groups



=cut






%TICKET_METAPRINCIPALS = (
    Owner     => 'The owner of a ticket',                             # loc_pair
    Requestor => 'The requestor of a ticket',                         # loc_pair
    Cc        => 'The CC of a ticket',                                # loc_pair
    AdminCc   => 'The administrative CC of a ticket',                 # loc_pair
);




=head2 LoadByValues PARAMHASH

Load an ACE by specifying a paramhash with the following fields:

              PrincipalId => undef,
              PrincipalType => undef,
	      RightName => undef,

        And either:

	      Object => undef,

            OR

	      ObjectType => undef,
	      ObjectId => undef

=cut

sub LoadByValues {
    my $self = shift;
    my %args = ( PrincipalId   => undef,
                 PrincipalType => undef,
                 RightName     => undef,
                 Object    => undef,
                 ObjectId    => undef,
                 ObjectType    => undef,
                 @_ );

    if ( $args{'RightName'} ) {
        my $canonic_name = $self->CanonicalizeRightName( $args{'RightName'} );
        unless ( $canonic_name ) {
            return ( 0, $self->loc("Invalid right. Couldn't canonicalize right '[_1]'", $args{'RightName'}) );
        }
        $args{'RightName'} = $canonic_name;
    }

    my $princ_obj;
    ( $princ_obj, $args{'PrincipalType'} ) =
      $self->_CanonicalizePrincipal( $args{'PrincipalId'},
                                     $args{'PrincipalType'} );

    unless ( $princ_obj->id ) {
        return ( 0,
                 $self->loc( 'Principal [_1] not found.', $args{'PrincipalId'} )
        );
    }

    my ($object, $object_type, $object_id) = $self->_ParseObjectArg( %args );
    unless( $object ) {
	return ( 0, $self->loc("System error. Right not granted.") );
    }

    $self->LoadByCols( PrincipalId   => $princ_obj->Id,
                       PrincipalType => $args{'PrincipalType'},
                       RightName     => $args{'RightName'},
                       ObjectType    => $object_type,
                       ObjectId      => $object_id);

    #If we couldn't load it.
    unless ( $self->Id ) {
        return ( 0, $self->loc("ACE not found") );
    }

    # if we could
    return ( $self->Id, $self->loc("Right Loaded") );

}



=head2 Create <PARAMS>

PARAMS is a parameter hash with the following elements:

   PrincipalId => The id of an RT::Principal object
   PrincipalType => "User" "Group" or any Role type
   RightName => the name of a right. in any case


    Either:

   Object => An object to create rights for. ususally, an RT::Queue or RT::Group
             This should always be a DBIx::SearchBuilder::Record subclass

        OR

   ObjectType => the type of the object in question (ref ($object))
   ObjectId => the id of the object in question $object->Id



   Returns a tuple of (STATUS, MESSAGE);  If the call succeeded, STATUS is true. Otherwise it's false.



=cut

sub Create {
    my $self = shift;
    my %args = (
        PrincipalId   => undef,
        PrincipalType => undef,
        RightName     => undef,
        Object        => undef,
        @_
    );

    unless ( $args{'RightName'} ) {
        return ( 0, $self->loc('No right specified') );
    }

    #if we haven't specified any sort of right, we're talking about a global right
    if (!defined $args{'Object'} && !defined $args{'ObjectId'} && !defined $args{'ObjectType'}) {
        $args{'Object'} = $RT::System;
    }
    ($args{'Object'}, $args{'ObjectType'}, $args{'ObjectId'}) = $self->_ParseObjectArg( %args );
    unless( $args{'Object'} ) {
	return ( 0, $self->loc("System error. Right not granted.") );
    }

    # Validate the principal
    my $princ_obj;
    ( $princ_obj, $args{'PrincipalType'} ) =
      $self->_CanonicalizePrincipal( $args{'PrincipalId'},
                                     $args{'PrincipalType'} );

    unless ( $princ_obj->id ) {
        return ( 0,
                 $self->loc( 'Principal [_1] not found.', $args{'PrincipalId'} )
        );
    }

    # }}}

    # Check the ACL

    if (ref( $args{'Object'}) eq 'RT::Group' ) {
        unless ( $self->CurrentUser->HasRight( Object => $args{'Object'},
                                                  Right => 'AdminGroup' )
          ) {
            return ( 0, $self->loc('Permission Denied') );
        }
    }

    else {
        unless ( $self->CurrentUser->HasRight( Object => $args{'Object'}, Right => 'ModifyACL' )) {
            return ( 0, $self->loc('Permission Denied') );
        }
    }
    # }}}

    # Canonicalize and check the right name
    my $canonic_name = $self->CanonicalizeRightName( $args{'RightName'} );
    unless ( $canonic_name ) {
        return ( 0, $self->loc("Invalid right. Couldn't canonicalize right '[_1]'", $args{'RightName'}) );
    }
    $args{'RightName'} = $canonic_name;

    #check if it's a valid RightName
    if ( $args{'Object'}->can('AvailableRights') ) {
        my $available = $args{'Object'}->AvailableRights;
        unless ( grep $_ eq $args{'RightName'}, map $self->CanonicalizeRightName( $_ ), keys %$available ) {
            $RT::Logger->warning(
                "Couldn't validate right name '$args{'RightName'}'"
                ." for object of ". ref( $args{'Object'} ) ." class"
            );
            return ( 0, $self->loc('Invalid right') );
        }
    }
    # }}}

    # Make sure the right doesn't already exist.
    $self->LoadByCols( PrincipalId   => $princ_obj->id,
                       PrincipalType => $args{'PrincipalType'},
                       RightName     => $args{'RightName'},
                       ObjectType    => $args{'ObjectType'},
                       ObjectId      => $args{'ObjectId'},
                   );
    if ( $self->Id ) {
        return ( 0, $self->loc('That principal already has that right') );
    }

    my $id = $self->SUPER::Create( PrincipalId   => $princ_obj->id,
                                   PrincipalType => $args{'PrincipalType'},
                                   RightName     => $args{'RightName'},
                                   ObjectType    => ref( $args{'Object'} ),
                                   ObjectId      => $args{'Object'}->id,
                               );

    #Clear the key cache. TODO someday we may want to just clear a little bit of the keycache space. 
    RT::Principal->InvalidateACLCache();

    if ( $id ) {
        return ( $id, $self->loc('Right Granted') );
    }
    else {
        return ( 0, $self->loc('System error. Right not granted.') );
    }
}



=head2 Delete { InsideTransaction => undef}

Delete this object. This method should ONLY ever be called from RT::User or RT::Group (or from itself)
If this is being called from within a transaction, specify a true value for the parameter InsideTransaction.
Really, DBIx::SearchBuilder should use and/or fake subtransactions

This routine will also recurse and delete any delegations of this right

=cut

sub Delete {
    my $self = shift;

    unless ( $self->Id ) {
        return ( 0, $self->loc('Right not loaded.') );
    }

    # A user can delete an ACE if the current user has the right to modify it and it's not a delegated ACE
    # or if it's a delegated ACE and it was delegated by the current user
    unless ($self->CurrentUser->HasRight(Right => 'ModifyACL', Object => $self->Object)) {
        return ( 0, $self->loc('Permission Denied') );
    }
    $self->_Delete(@_);
}

# Helper for Delete with no ACL check
sub _Delete {
    my $self = shift;
    my %args = ( InsideTransaction => undef,
                 @_ );

    my $InsideTransaction = $args{'InsideTransaction'};

    $RT::Handle->BeginTransaction() unless $InsideTransaction;

    my ( $val, $msg ) = $self->SUPER::Delete(@_);

    if ($val) {
	#Clear the key cache. TODO someday we may want to just clear a little bit of the keycache space. 
	# TODO what about the groups key cache?
	RT::Principal->InvalidateACLCache();
        $RT::Handle->Commit() unless $InsideTransaction;
        return ( $val, $self->loc('Right revoked') );
    }

    $RT::Handle->Rollback() unless $InsideTransaction;
    return ( 0, $self->loc('Right could not be revoked') );
}



=head2 _BootstrapCreate

Grant a right with no error checking and no ACL. this is _only_ for 
installation. If you use this routine without the author's explicit 
written approval, he will hunt you down and make you spend eternity
translating mozilla's code into FORTRAN or intercal.

If you think you need this routine, you've mistaken. 

=cut

sub _BootstrapCreate {
    my $self = shift;
    my %args = (@_);

    # When bootstrapping, make sure we get the _right_ users
    if ( $args{'UserId'} ) {
        my $user = RT::User->new( $self->CurrentUser );
        $user->Load( $args{'UserId'} );
        delete $args{'UserId'};
        $args{'PrincipalId'}   = $user->PrincipalId;
        $args{'PrincipalType'} = 'User';
    }

    my $id = $self->SUPER::Create(%args);

    if ( $id > 0 ) {
        return ($id);
    }
    else {
        $RT::Logger->err('System error. right not granted.');
        return (undef);
    }

}



sub RightName {
    my $self = shift;
    my $val = $self->_Value('RightName');
    return $val unless $val;

    my $available = $self->Object->AvailableRights;
    foreach my $right ( keys %$available ) {
        return $right if $val eq $self->CanonicalizeRightName($right);
    }

    $RT::Logger->error("Invalid right. Couldn't canonicalize right '$val'");
    return $val;
}

=head2 CanonicalizeRightName <RIGHT>

Takes a queue or system right name in any case and returns it in
the correct case. If it's not found, will return undef.

=cut

sub CanonicalizeRightName {
    my $self  = shift;
    return $LOWERCASERIGHTNAMES{ lc shift };
}




=head2 Object

If the object this ACE applies to is a queue, returns the queue object. 
If the object this ACE applies to is a group, returns the group object. 
If it's the system object, returns undef. 

If the user has no rights, returns undef.

=cut




sub Object {
    my $self = shift;

    my $appliesto_obj;

    if ($self->__Value('ObjectType') && $OBJECT_TYPES{$self->__Value('ObjectType')} ) {
        $appliesto_obj =  $self->__Value('ObjectType')->new($self->CurrentUser);
        unless (ref( $appliesto_obj) eq $self->__Value('ObjectType')) {
            return undef;
        }
        $appliesto_obj->Load( $self->__Value('ObjectId') );
        return ($appliesto_obj);
     }
    else {
        $RT::Logger->warning( "$self -> Object called for an object "
                              . "of an unknown type:"
                              . $self->__Value('ObjectType') );
        return (undef);
    }
}



=head2 PrincipalObj

Returns the RT::Principal object for this ACE. 

=cut

sub PrincipalObj {
    my $self = shift;

    my $princ_obj = RT::Principal->new( $self->CurrentUser );
    $princ_obj->Load( $self->__Value('PrincipalId') );

    unless ( $princ_obj->Id ) {
        $RT::Logger->err(
                   "ACE " . $self->Id . " couldn't load its principal object" );
    }
    return ($princ_obj);

}




sub _Set {
    my $self = shift;
    return ( 0, $self->loc("ACEs can only be created and deleted.") );
}



sub _Value {
    my $self = shift;

    if ( $self->PrincipalObj->IsGroup
            && $self->PrincipalObj->Object->HasMemberRecursively(
                                                $self->CurrentUser->PrincipalObj
            )
      ) {
        return ( $self->__Value(@_) );
    }
    elsif ( $self->CurrentUser->HasRight(Right => 'ShowACL', Object => $self->Object) ) {
        return ( $self->__Value(@_) );
    }
    else {
        return undef;
    }
}





=head2 _CanonicalizePrincipal (PrincipalId, PrincipalType)

Takes a principal id and a principal type.

If the principal is a user, resolves it to the proper acl equivalence group.
Returns a tuple of  (RT::Principal, PrincipalType)  for the principal we really want to work with

=cut

sub _CanonicalizePrincipal {
    my $self       = shift;
    my $princ_id   = shift;
    my $princ_type = shift || '';

    my $princ_obj = RT::Principal->new($RT::SystemUser);
    $princ_obj->Load($princ_id);

    unless ( $princ_obj->Id ) {
        use Carp;
        $RT::Logger->crit(Carp::cluck);
        $RT::Logger->crit("Can't load a principal for id $princ_id");
        return ( $princ_obj, undef );
    }

    # Rights never get granted to users. they get granted to their 
    # ACL equivalence groups
    if ( $princ_type eq 'User' ) {
        my $equiv_group = RT::Group->new( $self->CurrentUser );
        $equiv_group->LoadACLEquivalenceGroup($princ_obj);
        unless ( $equiv_group->Id ) {
            $RT::Logger->crit( "No ACL equiv group for princ " . $princ_obj->id );
            return ( RT::Principal->new($RT::SystemUser), undef );
        }
        $princ_obj  = $equiv_group->PrincipalObj();
        $princ_type = 'Group';

    }
    return ( $princ_obj, $princ_type );
}

sub _ParseObjectArg {
    my $self = shift;
    my %args = ( Object    => undef,
                 ObjectId    => undef,
                 ObjectType    => undef,
                 @_ );

    if( $args{'Object'} && ($args{'ObjectId'} || $args{'ObjectType'}) ) {
	$RT::Logger->crit( "Method called with an ObjectType or an ObjectId and Object args" );
	return ();
    } elsif( $args{'Object'} && !UNIVERSAL::can($args{'Object'},'id') ) {
	$RT::Logger->crit( "Method called called Object that has no id method" );
	return ();
    } elsif( $args{'Object'} ) {
	my $obj = $args{'Object'};
	return ($obj, ref $obj, $obj->id);
    } elsif ( $args{'ObjectType'} ) {
	my $obj =  $args{'ObjectType'}->new( $self->CurrentUser );
	$obj->Load( $args{'ObjectId'} );
	return ($obj, ref $obj, $obj->id);
    } else {
	$RT::Logger->crit( "Method called with wrong args" );
	return ();
    }
}


1;
