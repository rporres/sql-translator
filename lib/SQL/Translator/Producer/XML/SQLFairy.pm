package SQL::Translator::Producer::XML::SQLFairy;

# -------------------------------------------------------------------
# $Id: SQLFairy.pm,v 1.13 2004-07-08 19:34:29 grommit Exp $
# -------------------------------------------------------------------
# Copyright (C) 2003 Ken Y. Clark <kclark@cpan.org>,
#                    darren chamberlain <darren@cpan.org>,
#                    Chris Mungall <cjm@fruitfly.org>,
#                    Mark Addison <mark.addison@itn.co.uk>.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; version 2.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
# 02111-1307  USA
# -------------------------------------------------------------------

=pod

=head1 NAME

SQL::Translator::Producer::XML::SQLFairy - SQLFairy's default XML format

=head1 SYNOPSIS

  use SQL::Translator;

  my $t              = SQL::Translator->new(
      from           => 'MySQL',
      to             => 'XML-SQLFairy',
      filename       => 'schema.sql',
      show_warnings  => 1,
      add_drop_table => 1,
  );

  print $t->translate;

=head1 DESCRIPTION

Creates XML output of a schema, in SQLFairy format XML.

The XML lives in the http://sqlfairy.sourceforge.net/sqlfairy.xml namespace.
With a root element of <schema>.

Objects in the schema are mapped to tags of the same name as the objects class.

The attributes of the objects (e.g. $field->name) are mapped to attributes of
the tag, except for sql, comments and action, which get mapped to child data
elements.

List valued attributes (such as the list of fields in an index)
get mapped to a comma seperated list of values in the attribute.

Child objects, such as a tables fields, get mapped to child tags wrapped in a
set of container tags using the plural of their contained classes name.

e.g.

    <schema name="" database=""
      xmlns="http://sqlfairy.sourceforge.net/sqlfairy.xml">

      <table name="Story" order="1">

        <fields>
          <field name="created" data_type="datetime" size="0"
            is_nullable="1" is_auto_increment="0" is_primary_key="0"
            is_foreign_key="0" order="1">
            <comments></comments>
          </field>
          <field name="id" data_type="BIGINT" size="20"
            is_nullable="0" is_auto_increment="1" is_primary_key="1"
            is_foreign_key="0" order="3">
            <comments></comments>
          </field>
          ...
        </fields>

        <indices>
          <index name="foobar" type="NORMAL" fields="foo,bar" options="" />
        </indices>

      </table>

      <view name="email_list" fields="email" order="1">
        <sql>SELECT email FROM Basic WHERE email IS NOT NULL</sql>
      </view>

    </schema>

To see a complete example of the XML translate one of your schema :)

  $ sqlt -f MySQL -t XML-SQLFairy schema.sql

=head1 ARGS

Doesn't take any extra arguments.

=head1 LEGACY FORMAT

The previous version of the SQLFairy XML allowed the attributes of the the
schema objects to be written as either xml attributes or as data elements, in
any combination. The old producer could produce attribute only or data element
only versions. While this allowed for lots of flexibility in writing the XML
the result is a great many possible XML formats, not so good for DTD writing,
XPathing etc! So we have moved to a fixed version described above.

This version of the producer will now only produce the new style XML.
To convert your old format files simply pass them through the translator;

 sqlt -f XML-SQLFairy -t XML-SQLFairy schema-old.xml > schema-new.xml

=cut

use strict;
use vars qw[ $VERSION @EXPORT_OK ];
$VERSION = sprintf "%d.%02d", q$Revision: 1.13 $ =~ /(\d+)\.(\d+)/;

use Exporter;
use base qw(Exporter);
@EXPORT_OK = qw(produce);

use IO::Scalar;
use SQL::Translator::Utils qw(header_comment debug);
BEGIN {
    # Will someone fix XML::Writer already?
    local $^W = 0;
    require XML::Writer;
    import XML::Writer;
}

my $Namespace = 'http://sqlfairy.sourceforge.net/sqlfairy.xml';
my $Name      = 'sqlf';
my $PArgs     = {};

sub produce {
    my $translator  = shift;
    my $schema      = $translator->schema;
    $PArgs          = $translator->producer_args;
    my $io          = IO::Scalar->new;
    my $xml         = XML::Writer->new(
        OUTPUT      => $io,
        NAMESPACES  => 1,
        PREFIX_MAP  => { $Namespace => $Name },
        DATA_MODE   => 1,
        DATA_INDENT => 2,
    );

    $xml->xmlDecl('UTF-8');
    $xml->comment(header_comment('', ''));
    #$xml->startTag([ $Namespace => 'schema' ]);
    xml_obj($xml, $schema,
        tag => "schema", methods => [qw/name database/], end_tag => 0 );

    #
    # Table
    #
    for my $table ( $schema->get_tables ) {
        debug "Table:",$table->name;
        xml_obj($xml, $table,
             tag => "table", methods => [qw/name order/], end_tag => 0 );

        #
        # Fields
        #
        $xml->startTag( [ $Namespace => 'fields' ] );
        for my $field ( $table->get_fields ) {
            debug "    Field:",$field->name;
            xml_obj($xml, $field,
                tag     =>"field",
                end_tag => 1,
                methods =>[qw/name data_type size is_nullable default_value
                    is_auto_increment is_primary_key is_foreign_key comments order
                /],
            );
        }
        $xml->endTag( [ $Namespace => 'fields' ] );

        #
        # Indices
        #
        $xml->startTag( [ $Namespace => 'indices' ] );
        for my $index ( $table->get_indices ) {
            debug "Index:",$index->name;
            xml_obj($xml, $index,
                tag     => "index",
                end_tag => 1,
                methods =>[qw/ name type fields options/],
            );
        }
        $xml->endTag( [ $Namespace => 'indices' ] );

        #
        # Constraints
        #
        $xml->startTag( [ $Namespace => 'constraints' ] );
        for my $index ( $table->get_constraints ) {
            debug "Constraint:",$index->name;
            xml_obj($xml, $index,
                tag     => "constraint",
                end_tag => 1,
                methods =>[qw/
                    name type fields reference_table reference_fields
                    on_delete on_update match_type expression options deferrable
                    /],
            );
        }
        $xml->endTag( [ $Namespace => 'constraints' ] );

        $xml->endTag( [ $Namespace => 'table' ] );
    }

    #
    # Views
    #
    for my $foo ( $schema->get_views ) {
        xml_obj($xml, $foo, tag => "view",
        methods => [qw/name sql fields order/], end_tag => 1 );
    }

    #
    # Tiggers
    #
    for my $foo ( $schema->get_triggers ) {
        xml_obj($xml, $foo, tag => "trigger",
        methods => [qw/name database_event action on_table perform_action_when
        fields order/], end_tag => 1 );
    }

    #
    # Procedures
    #
    for my $foo ( $schema->get_procedures ) {
        xml_obj($xml, $foo, tag => "procedure",
        methods => [qw/name sql parameters owner comments order/], end_tag=>1 );
    }

    $xml->endTag([ $Namespace => 'schema' ]);
    $xml->end;

    return $io;
}

# -------------------------------------------------------------------
#
# Takes an XML Write, Schema::* object and list of method names
# and writes the obect out as XML. All methods values are written as attributes
# except for comments, sql and action which get written as child data elements.
#
# The attributes, tags are written in the same order as the method names are
# passed.
#
# TODO
# - Should the Namespace be passed in instead of global? Pass in the same
#   as Writer ie [ NS => TAGNAME ]
#
sub xml_obj {
    my ($xml, $obj, %args) = @_;
    my $tag                = $args{'tag'}              || '';
    my $end_tag            = $args{'end_tag'}          || '';
    my @meths              = @{ $args{'methods'} };
    my $empty_tag          = 0;

    # Use array to ensure consistant (ie not hash) ordering of attribs
    # The order comes from the meths list passed in.
    my @tags;
    my @attr;
    foreach ( grep { defined $obj->$_ } @meths ) {
        my $what = m/^sql|comments|action$/ ? \@tags : \@attr;
        my $val = $obj->$_;
        $val = ref $val eq 'ARRAY' ? join(',', @$val) : $val;
        push @$what, $_ => $val;
    };
    my $child_tags = @tags;
    $end_tag && !$child_tags
        ? $xml->emptyTag( [ $Namespace => $tag ], @attr )
        : $xml->startTag( [ $Namespace => $tag ], @attr );
    while ( my ($name,$val) = splice @tags,0,2 ) {
        $xml->dataElement( [ $Namespace => $name ], $val );
    }
    $xml->endTag( [ $Namespace => $tag ] ) if $child_tags && $end_tag;
}

1;

# -------------------------------------------------------------------
# The eyes of fire, the nostrils of air,
# The mouth of water, the beard of earth.
# William Blake
# -------------------------------------------------------------------

=pod

=head1 AUTHORS

Ken Y. Clark E<lt>kclark@cpan.orgE<gt>,
Darren Chamberlain E<lt>darren@cpan.orgE<gt>,
Mark Addison E<lt>mark.addison@itn.co.ukE<gt>.

=head1 SEE ALSO

perl(1), SQL::Translator, SQL::Translator::Parser::XML::SQLFairy,
SQL::Translator::Schema, XML::Writer.

=cut
