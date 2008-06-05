% $Id$

%% @author Jean-Sébastien Pédron <js.pedron@meetic-corp.com>

%% @doc
%% The module <strong>{@module}</strong> provides functions to handle
%% JID.

-module(exmpp_jid).
-vsn('$Revision$').

-include("exmpp.hrl").

% Conversion.
-export([
  make_jid/3,
  make_bare_jid/2,
  jid_to_bare_jid/1,
  bare_jid_to_jid/2
]).

% Parsing.
-export([
  string_to_jid/1,
  string_to_bare_jid/1
]).

% Serialization.
-export([
  jid_to_string/1,
  bare_jid_to_string/1
]).

% Comparison.
-export([
  compare_jids/2,
  compare_bare_jids/2,
  compare_domains/2
]).

% Checks.
-export([
  is_jid/1
]).

-define(NODE_MAX_LENGTH,     1023).
-define(DOMAIN_MAX_LENGTH,   1023).
-define(RESOURCE_MAX_LENGTH, 1023).
-define(BARE_JID_MAX_LENGTH, ?NODE_MAX_LENGTH + 1 + ?DOMAIN_MAX_LENGTH).
-define(JID_MAX_LENGTH,      ?BARE_JID_MAX_LENGTH + 1 + ?RESOURCE_MAX_LENGTH).

% --------------------------------------------------------------------
% JID creation & conversion.
% --------------------------------------------------------------------

%% @spec (Node, Domain) -> Bare_Jid
%%     Node = string()
%%     Domain = string()
%%     Bare_Jid = jid()
%% @throws {jid, make, domain_too_long, {Node, Domain, undefined}} |
%%         {jid, make, invalid_domain,  {Node, Domain, undefined}} |
%%         {jid, make, node_too_long,   {Node, Domain, undefined}} |
%%         {jid, make, invalid_node,    {Node, Domain, undefined}}
%% @doc Create a bare JID.

make_bare_jid(Node, Domain)
  when length(Domain) > ?DOMAIN_MAX_LENGTH ->
    throw({jid, make, domain_too_long, {Node, Domain, undefined}});
make_bare_jid(undefined, Domain) ->
    case exmpp_stringprep:nameprep(Domain) of
        error ->
            throw({jid, make, invalid_domain, {undefined, Domain, undefined}});
        LDomain ->
            #jid{
              node = undefined,
              domain = Domain,
              resource = undefined,
              lnode = undefined,
              ldomain = LDomain,
              lresource = undefined
            }
    end;
make_bare_jid(Node, Domain)
  when length(Node) > ?NODE_MAX_LENGTH ->
    throw({jid, make, node_too_long, {Node, Domain, undefined}});
make_bare_jid(Node, Domain) ->
    case exmpp_stringprep:nodeprep(Node) of
        error ->
            throw({jid, make, invalid_node, {Node, Domain, undefined}});
        LNode ->
            case exmpp_stringprep:nameprep(Domain) of
                error ->
                    throw({jid, make, invalid_domain,
                        {Node, Domain, undefined}});
                LDomain ->
                    #jid{
                      node = Node,
                      domain = Domain,
                      resource = undefined,
                      lnode = LNode,
                      ldomain = LDomain,
                      lresource = undefined
                    }
            end
    end.

%% @spec (Node, Domain, Resource) -> Jid
%%     Node = string()
%%     Domain = string()
%%     Resource = string()
%%     Jid = jid()
%% @doc Create a full JID.

make_jid(Node, Domain, undefined) ->
    make_bare_jid(Node, Domain);
make_jid(Node, Domain, random) ->
    Resource = generate_resource(),
    make_jid(Node, Domain, Resource);
make_jid(Node, Domain, Resource) ->
    Jid = make_bare_jid(Node, Domain),
    bare_jid_to_jid(Jid, Resource).

%% @spec (Jid) -> Bare_Jid
%%     Jid = jid()
%%     Bare_Jid = jid()
%% @doc Convert a full JID to its bare version.

jid_to_bare_jid(Jid) ->
    Jid#jid{
      resource = undefined,
      lresource = undefined
    }.

%% @spec (Bare_Jid, Resource) -> Jid
%%     Bare_Jid = jid()
%%     Resource = string()
%%     Jid = jid()
%% @throws {jid, convert, resource_too_long, {Node, Domain, Resource}} |
%%         {jid, convert, invalid_resource,  {Node, Domain, Resource}}
%% @doc Convert a bare JID to its full version.

bare_jid_to_jid(Jid, undefined) ->
    Jid;
bare_jid_to_jid(Jid, Resource)
  when length(Resource) > ?RESOURCE_MAX_LENGTH ->
    throw({jid, convert, resource_too_long,
        {Jid#jid.node, Jid#jid.domain, Resource}});
bare_jid_to_jid(Jid, Resource) ->
    case exmpp_stringprep:resourceprep(Resource) of
        error ->
            throw({jid, convert, invalid_resource,
                {Jid#jid.node, Jid#jid.domain, Resource}});
        LResource ->
            Jid#jid{
              resource = Resource,
              lresource = LResource
            }
    end.

% --------------------------------------------------------------------
% JID parsing.
% --------------------------------------------------------------------

%% @spec (String) -> Jid
%%     String = string()
%%     Jid = jid()
%% @throws {jid, parse, jid_too_long, {String, undefined, undefined}} |
%%         {jid, parse, Reason,       {String, undefined, undefined}}
%% @doc Parse a string and create a full JID.

string_to_jid(String)
  when length(String) > ?JID_MAX_LENGTH ->
    throw({jid, parse, jid_too_long, {String, undefined, undefined}});
string_to_jid(String) ->
    case parse_jid(full, String, "") of
        {error, Reason} ->
            throw({jid, parse, Reason, {String, undefined, undefined}});
        Jid ->
            Jid
    end.

%% @spec (String) -> Bare_Jid
%%     String = string()
%%     Bare_Jid = jid()
%% @throws {jid, parse, jid_too_long, {String, undefined, undefined}} |
%%         {jid, parse, Reason,       {String, undefined, undefined}}
%% @doc Parse a string and create a bare JID.

string_to_bare_jid(String)
  when length(String) > ?BARE_JID_MAX_LENGTH ->
    throw({jid, parse, jid_too_long, {String, undefined, undefined}});
string_to_bare_jid(String) ->
    case parse_jid(bare, String, "") of
        {error, Reason} ->
            throw({jid, parse, Reason, {String, undefined, undefined}});
        Bare_Jid ->
            Bare_Jid
    end.

parse_jid(_Type, [$@ | _Rest], "") ->
    % Invalid JID of the form "@Domain".
    {error, unexpected_node_separator};
parse_jid(Type, [$@ | Rest], Node) ->
    % JID of the form "Node@Domain".
    parse_jid(Type, Rest, lists:reverse(Node), "");
parse_jid(_Type, [$/ | _Rest], "") ->
    % Invalid JID of the form "/Resource".
    {error, unexpected_resource_separator};
parse_jid(full, [$/], _Domain) ->
    % Invalid JID of the form "Domain/".
    {error, unexpected_end_of_string};
parse_jid(bare, [$/ | _Resource], Domain) ->
    % Valid JID of the form "Domain/Resource" (resource is dropped).
    make_bare_jid(undefined, lists:reverse(Domain));
parse_jid(full, [$/ | Resource], Domain) ->
    % Valid JID of the form "Domain/Resource".
    make_jid(undefined, lists:reverse(Domain), Resource);
parse_jid(Type, [C | Rest], Node_Or_Domain) ->
    % JID of the form "Node@Domain" or "Node@Domain/Resource".
    parse_jid(Type, Rest, [C | Node_Or_Domain]);
parse_jid(_Type, [], "") ->
    % Invalid JID of the form "".
    {error, unexpected_end_of_string};
parse_jid(bare, [], Domain) ->
    % Valid JID of the form "Domain".
    make_bare_jid(undefined, lists:reverse(Domain));
parse_jid(full, [], Domain) ->
    % Valid JID of the form "Domain".
    make_jid(undefined, lists:reverse(Domain), undefined).

parse_jid(_Type, [$@ | _Rest], _Node, _Domain) ->
    % Invalid JID of the form "Node@Domain@Domain".
    {error, unexpected_node_separator};
parse_jid(_Type, [$/ | _Rest], _Node, "") ->
    % Invalid JID of the form "Node@/Resource".
    {error, unexpected_resource_separator};
parse_jid(full, [$/], _Node, _Domain) ->
    % Invalid JID of the form "Node@Domain/".
    {error, unexpected_end_of_string};
parse_jid(bare, [$/ | _Rest], Node, Domain) ->
    % Valid JID of the form "Node@Domain/Resource" (resource is dropped).
    make_bare_jid(Node, lists:reverse(Domain));
parse_jid(full, [$/ | Resource], Node, Domain) ->
    % Valid JID of the form "Node@Domain/Resource".
    make_jid(Node, lists:reverse(Domain), Resource);
parse_jid(Type, [C | Rest], Node, Domain) ->
    % JID of the form "Node@Domain" or "Node@Domain/Resource".
    parse_jid(Type, Rest, Node, [C | Domain]);
parse_jid(_Type, [], _Node, "") ->
    % Invalid JID of the form "Node@".
    {error, unexpected_end_of_string};
parse_jid(bare, [], Node, Domain) ->
    % Valid JID of the form "Node@Domain".
    make_bare_jid(Node, lists:reverse(Domain));
parse_jid(full, [], Node, Domain) ->
    % Valid JID of the form "Node@Domain".
    make_jid(Node, lists:reverse(Domain), undefined).

% --------------------------------------------------------------------
% JID serialization.
% --------------------------------------------------------------------

%% @spec (Jid) -> String
%%     Jid = jid()
%%     String = string()
%% @doc Stringify a full JID.

jid_to_string(#jid{node = Node, domain = Domain, resource = Resource}) ->
    jid_to_string(Node, Domain, Resource).

jid_to_string(Node, Domain, Resource) ->
    S1 = bare_jid_to_string(Node, Domain),
    case Resource of
        ""        -> S1;
        undefined -> S1;
        _         -> S1 ++ "/" ++ Resource
    end.

%% @spec (Bare_Jid) -> String
%%     Bare_Jid = jid()
%%     String = string()
%% @doc Stringify a bare JID.

bare_jid_to_string(#jid{node = Node, domain = Domain}) ->
    bare_jid_to_string(Node, Domain).

bare_jid_to_string(Node, Domain) ->
    S1 = case Node of
        ""        -> "";
        undefined -> "";
        _         -> Node ++ "@"
    end,
    S1 ++ Domain.

% --------------------------------------------------------------------
% JID comparison.
% --------------------------------------------------------------------

%% @spec (Jid1, Jid2) -> bool()
%%     Jid1 = jid()
%%     Jid2 = jid()
%% @doc Compare full JIDs.

compare_jids(
  #jid{lnode = LNode, ldomain = LDomain, lresource = LResource},
  #jid{lnode = LNode, ldomain = LDomain, lresource = LResource}) ->
    true;
compare_jids(_Jid1, _Jid2) ->
    false.

%% @spec (Bare_Jid1, Bare_Jid2) -> bool()
%%     Bare_Jid1 = jid()
%%     Bare_Jid2 = jid()
%% @doc Compare bare JIDs.

compare_bare_jids(
  #jid{lnode = LNode, ldomain = LDomain},
  #jid{lnode = LNode, ldomain = LDomain}) ->
    true;
compare_bare_jids(_Jid1, _Jid2) ->
    false.

%% @spec (Jid1, Jid2) -> bool()
%%     Jid1 = jid()
%%     Jid2 = jid()
%% @doc Compare JID's domain.

compare_domains(
  #jid{ldomain = LDomain},
  #jid{ldomain = LDomain}) ->
    true;
compare_domains(_Jid1, _Jid2) ->
    false.

% --------------------------------------------------------------------
% JID checks.
% --------------------------------------------------------------------

%% @spec (Jid) -> bool()
%%     Jid = jid()
%% @doc Tell if the argument is a JID.

is_jid(JID) when record(JID, jid) ->
    true;
is_jid(_) ->
    false.

% --------------------------------------------------------------------
% Helper functions
% --------------------------------------------------------------------

% We do not use random generator to avoid having to decide when and 
% how to seed the Erlang random number generator.
generate_resource() ->
    {A, B, C} = erlang:now(),
    lists:flatten(["exmpp#",
      integer_to_list(A),
      integer_to_list(B),
      integer_to_list(C)]
    ).

% --------------------------------------------------------------------
% Documentation / type definitions.
% --------------------------------------------------------------------

%% @type jid() = {jid, Node, Domain, Resource}
%%     Node = string()
%%     Domain = string()
%%     Resource = string().
%% Represents JID.