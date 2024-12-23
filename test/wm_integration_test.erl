%%
%%
%%    Licensed under the Apache License, Version 2.0 (the "License");
%%    you may not use this file except in compliance with the License.
%%    You may obtain a copy of the License at
%%
%%        http://www.apache.org/licenses/LICENSE-2.0
%%
%%    Unless required by applicable law or agreed to in writing, software
%%    distributed under the License is distributed on an "AS IS" BASIS,
%%    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%    See the License for the specific language governing permissions and
%%    limitations under the License.
-module(wm_integration_test).
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-include("webmachine.hrl").

integration_test_() ->
    {foreach,
     %% Setup
     fun() ->
             ibrowse:start(),
             DL = [{["wm_echo_host_header", '*'], wm_echo_host_header, []}],
             case inet:getaddrs("localhost", inet6) of
                 {ok, [_|_]} ->
                     %% Listen on both ipv4 and ipv6 so we can test both.
                     wm_integration_test_util:start(?MODULE, "::0", DL);
                 {ok, []} ->
                     ?debugMsg("IPv6 unavailable, tests covering v6 addresses will be skipped"),
                     wm_integration_test_util:start(?MODULE, "0.0.0.0", DL)
             end
     end,
     %% Cleanup
     fun(Ctx) ->
             wm_integration_test_util:stop(Ctx)
     end,
     %% Test functions provided with context from setup
     [fun(Ctx) ->
              {Title, {spawn, {with, Ctx, [fun(C) -> ?debugFmt("~s: ~p~n", [Title, self()]), T(C) end]}}}
      end
      || {Title, T} <- integration_tests()
     ]
    }.

integration_tests() ->
    [{"test_host_header_localhost", fun test_host_header_localhost/1},
     {"test_host_header_127", fun test_host_header_127/1},
     {"test_host_header_ipv6", fun test_host_header_ipv6/1},
     {"test_host_header_ipv6_curl", fun test_host_header_ipv6_curl/1}].

test_host_header_localhost(Ctx) ->
    ExpectHost = add_port(Ctx, "localhost"),
    verify_host_header(Ctx, "localhost", ExpectHost, <<"localhost">>).

test_host_header_127(Ctx) ->
    ExpectHost = add_port(Ctx, "127.0.0.1"),
    verify_host_header(Ctx, "127.0.0.1", ExpectHost, <<"127.0.0.1">>).

test_host_header_ipv6(Ctx) ->
    %% Bare ipv6 addresses must be enclosed in square
    %% brackets. ibrowse does the right thing in parsing the URL, but
    %% does not set the Host header correctly where it adds the bare
    %% host rather than the bracketed version.
    %%
    %% It is likely there are other HTTP clients that will make send
    %% such a Host header, it is worth testing that we handle it
    %% reasonably.
    ListenAddr = wm_integration_test_util:get_addr(Ctx),
    if
        is_tuple(ListenAddr) andalso tuple_size(ListenAddr) == 8 ->
            ExpectHost = add_port(Ctx, "::1"),
            ExpectTokens = <<"[", ExpectHost/binary, "]">>,
            verify_host_header(Ctx, "[::1]", ExpectHost, ExpectTokens, true);
        true ->
            ?debugMsg("Skipping test_host_header_ipv6, not listening on v6 address")
    end.

test_host_header_ipv6_curl(Ctx) ->
    ListenAddr = wm_integration_test_util:get_addr(Ctx),
    if
        is_tuple(ListenAddr) andalso tuple_size(ListenAddr) == 8 ->
            %% curl has the desired client behavior for ipv6
            case os:find_executable("curl") of
                false ->
                    ?debugMsg("curl not found: skipping test_host_header_ipv6_curl");
                _ ->
                    Port = wm_integration_test_util:get_port(Ctx),
                    P = erlang:integer_to_list(Port),
                    Cmd = "curl -gs http://[::1]:" ++ P ++ "/wm_echo_host_header",
                    Got = wm_echo_host_header:parse_body(erlang:list_to_binary(os:cmd(Cmd))),
                    ?assertEqual(add_port(Ctx, "[::1]"), proplists:get_value(<<"Host">>, Got)),
                    ?assertEqual(<<"[::1]">>, proplists:get_value(<<"HostTokens">>, Got))
            end;
        true ->
            ?debugMsg("Skipping test_host_header_ipv6_curl, not listening on v6 address")
    end.

url(Ctx, Host, Path) ->
    Port = erlang:integer_to_list(wm_integration_test_util:get_port(Ctx)),
    "http://" ++ Host ++ ":" ++ Port ++ slash(Path).

slash("/" ++ _Rest = Path) ->
    Path;
slash(Path) ->
    "/" ++ Path.

add_port(Ctx, Host) ->
    Port = wm_integration_test_util:get_port(Ctx),
    erlang:iolist_to_binary([Host, ":", erlang:integer_to_list(Port)]).

%% TODO: wm crashes if multiple Host headers are sent

verify_host_header(Ctx, Host, ExpectHostHeader, ExpectHostTokens) ->
    verify_host_header(Ctx, Host, ExpectHostHeader, ExpectHostTokens, false).

verify_host_header(Ctx, Host, ExpectHostHeader, ExpectHostTokens, PreferV6) ->
    Opts =
        case PreferV6 of
            true ->
                [{prefer_ipv6, true}];
            false ->
                []
        end,
    URL = url(Ctx, Host, "wm_echo_host_header"),
    {ok, Status, _Headers, Body} = ibrowse:send_req(URL, [], get, [], Opts),
    ?assertEqual("200", Status),
    Got = wm_echo_host_header:parse_body(Body),
    ?debugVal(Got),
    ?assertEqual(ExpectHostHeader, proplists:get_value(<<"Host">>, Got)),
    ?assertEqual(ExpectHostTokens, proplists:get_value(<<"HostTokens">>, Got)).

-endif.
