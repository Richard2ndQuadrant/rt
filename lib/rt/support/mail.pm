# $Header$
#

package rt;

#####
##### Mailing Routines
#####



sub template_replace_tokens {
    local ($template,$in_serial_num,$in_id, 
	   $in_custom_content, $in_current_user) = @_;
    
    &rt::req_in($in_serial_num,'_rt_system');
    &rt::transaction_in($in_id,'_rt_system') if $in_id;
    $template =~ s/%rtname%/$rtname/g;
    $template =~ s/%rtversion%/$rtversion/g;
    $template =~ s/%actor%/\'$in_current_user\' ($rt::$users{$in_current_user}{real_name})/g;
    $template =~ s/%owner%/$rt::$users{$rt::req[$in_serial_num]{owner}}{real_name} ($rt::$users{$rt::req[$in_serial_num]{owner}}{email})/g;
    $template =~ s/%subject%/$in_subject/g;
    $template =~ s/%serial_num%/$in_serial_num/g;
    $template =~ s/%mailalias%/$mail_alias/g;
    $template =~ s/%content%/$in_custom_content\n/g;
    $template =~ s/%req:(\w+)%/$rt::req[$in_serial_num]{$1}/g;
    $template =~ s/%trans:(\w+)%/$rt::req[$in_serial_num]{'trans'}[$in_id]{$1}/g;
    $template =~ s/%queue:(\w+)%/$rt::queues{$rt::req[$in_serial_num]{'queue_id'}}{$1}/g;

    if ($in_serial_num > 0){
      &req_in($in_serial_num,$in_current_user);
  	&transaction_in($in_id,$in_current_user) if $in_id;
	} 

    return ($template);
}


# The return value should specify whether an error has occurred or
# not, so errors might be returned to the UI. It seems to me the
# message is discarded anyway, so introducing the same array-scheme as
# elsewhere could be feasible in 1.0. I want to test the emails using
# Email::Valid - if and only if the module can be located in @INC.

sub template_mail{
    local ($in_template,$in_queue_id, $in_recipient, $in_cc, $in_bcc, 
	   $in_serial_num, $in_transaction, $in_subject, $in_current_user, 
	   $in_custom_content) = @_;
    my ($mailto, $template, $temp_mail_alias);
    
    # Everything except when using the 'correspondence' is
    # autogenerated, and should be marked as bulk:
    my $precedence=($in_template eq 'correspondence') ? '' : 'bulk';
    
    $template=&template_read($in_template, $in_queue_id);
    $template=&template_replace_tokens($template,$in_serial_num,$in_transaction, 
				       $in_custom_content, $in_current_user);
    $subject=&template_replace_tokens($subject,$in_serial_num,$in_transaction, 
				      $in_custom_content, $in_current_user);

    # This is very hack&slash. I don't want the mail headers to be
    # appended to correspondance mail. This dirty hack will remove it
    # from all mails - even though only the mail to the requestor is
    # important:
	
    # I'm too afraid of doing this, so i've commented it out for now
    # If someone comes up with a less crufty hack that only sends to the 
    # requestor, i'll take it
    # - jesse

    if (!$precedence) {
      #      $template =~ s/--- Headers Follow ---(.*)$//;
    }
    #    print STDERR "Debug 1\n";
    
    if (!$in_recipient && !$in_cc && !$in_bcc) {
      return("template_mail:No Recipient Specified!");
    }
    
    # The message will be killed by the mailing server if there are no
    # mail alias - and for the _rt_system there aren't really a
    # mail_alias:
    $temp_mail_alias = $rt::queues{"$in_queue_id"}{'mail_alias'}; 
    if (!$rt::queues{"$in_queue_id"}{'mail_alias'}) {
      $temp_mail_alias = $rt::mail_alias;
    }
    else {
      $temp_mail_alias = $rt::queues{"$in_queue_id"}{'mail_alias'};
    }
    

    if (!$rt::users{"$in_current_user"}{'real_name'}) {
      $friendly_name = "Request Tracker";

    }
    else {
      $friendly_name = $rt::users{"$in_current_user"}{'real_name'}." via RT";
    }
    
    #remove leading space
    $in_subject =~ s/^(\s*)//;

    open (MAIL, "|$rt::mailprog $rt::mail_options");
    
    print  MAIL "Subject: [$rt::rtname \#". $in_serial_num . "] ($in_queue_id) $in_subject
Reply-To: $friendly_name <$temp_mail_alias>
From: $friendly_name <$temp_mail_alias>
To: $in_recipient   
Cc: $in_cc
Bcc: $in_bcc
X-Request-ID: $in_serial_num
X-RT-Loop-Prevention: $rt::rtname
X-Sender: $in_current_user
X-Managed-By: Request Tracker $rt::rtversion (http://www.fsck.com/projects/rt)
Precedence: $precedence 

$template
-------------------------------------------- Managed by Request Tracker\n";
    if (close (MAIL)) {
      return("template_mail:Message Sent");
    } else {
      die "Could not send mail :(\n$!\nTried to launch this command: $rt::mailprog $rt::mail_options\n";
    }
  }

1;
