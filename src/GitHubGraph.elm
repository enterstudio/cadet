module GitHubGraph
    exposing
        ( Error
        , ID
        , Repo
        , Issue
        , IssueState(..)
        , Label
        , User
        , Project
        , ProjectColumn
        , ProjectColumnCard
        , CardLocation
        , CardContent(..)
        , PullRequest
        , PullRequestState(..)
        , Reactions
        , ReactionGroup
        , ReactionType(..)
        , TimelineEvent(..)
        , Milestone
        , MilestoneState(..)
        , IssueOrPRSelector
        , RepoSelector
        , fetchOrgRepos
        , fetchOrgProjects
        , fetchOrgProject
        , fetchProjectColumnCards
        , fetchRepo
        , fetchRepoIssues
        , fetchRepoIssue
        , fetchRepoPullRequests
        , fetchRepoPullRequest
        , fetchTimeline
        , moveCardAfter
        , addContentCard
        , addContentCardAfter
        , createRepoLabel
        , updateRepoLabel
        , deleteRepoLabel
        , closeIssue
        , addIssueLabels
        , removeIssueLabel
        , createRepoMilestone
        , deleteRepoMilestone
        , closeRepoMilestone
        , issueScore
        , pullRequestScore
        , reactionScore
        , labelEq
        , encodeRepo
        , decodeRepo
        , encodeIssue
        , decodeIssue
        , encodePullRequest
        , decodePullRequest
        , encodeUser
        , decodeUser
        , encodeProject
        , decodeProject
        , encodeProjectColumnCard
        , decodeProjectColumnCard
        )

import Date exposing (Date)
import Date.Format
import Dict
import GraphQL.Client.Http as GH
import GraphQL.Request.Builder as GB
import GraphQL.Request.Builder.Arg as GA
import GraphQL.Request.Builder.Variable as GV
import Http
import HttpBuilder
import Json.Decode as JD
import Json.Decode.Extra as JDE exposing ((|:))
import Json.Encode as JE
import Json.Encode.Extra as JEE
import Task exposing (Task)


type alias Token =
    String


type alias Error =
    GH.Error


type alias ID =
    String


type alias Repo =
    { id : ID
    , url : String
    , owner : String
    , name : String
    , labels : List Label
    , milestones : List Milestone
    }


type alias Issue =
    { id : ID
    , url : String
    , resourcePath : String
    , createdAt : Date
    , updatedAt : Date
    , state : IssueState
    , number : Int
    , title : String
    , commentCount : Int
    , reactions : Reactions
    , author : Maybe User
    , labels : List Label
    , cards : List CardLocation
    , milestone : Maybe Milestone
    }


type IssueState
    = IssueStateOpen
    | IssueStateClosed


type alias PullRequest =
    { id : ID
    , url : String
    , createdAt : Date
    , updatedAt : Date
    , state : PullRequestState
    , number : Int
    , title : String
    , commentCount : Int
    , reactions : Reactions
    , author : Maybe User
    , labels : List Label
    , cards : List CardLocation
    , additions : Int
    , deletions : Int
    , milestone : Maybe Milestone
    }


type PullRequestState
    = PullRequestStateOpen
    | PullRequestStateClosed
    | PullRequestStateMerged


type alias Label =
    { id : ID
    , name : String
    , color : String
    }


type alias Milestone =
    { id : ID
    , number : Int
    , title : String
    , state : MilestoneState
    , description : Maybe String
    }


type MilestoneState
    = MilestoneStateOpen
    | MilestoneStateClosed


type alias ReactionGroup =
    { type_ : ReactionType
    , count : Int
    }


type ReactionType
    = ReactionTypeThumbsUp
    | ReactionTypeThumbsDown
    | ReactionTypeLaugh
    | ReactionTypeHooray
    | ReactionTypeConfused
    | ReactionTypeHeart


type alias User =
    { id : ID
    , url : String
    , login : String
    , avatar : String
    }


type alias Reactions =
    List ReactionGroup


type alias Project =
    { id : ID
    , url : String
    , name : String
    , number : Int
    , columns : List ProjectColumn
    }


type alias ProjectColumn =
    { id : ID
    , name : String

    -- used to cross-reference with v3 hooks API
    , databaseId : Int
    }


type alias ProjectColumnCard =
    { id : ID
    , content : Maybe CardContent
    , note : Maybe String
    }


type CardContent
    = IssueCardContent Issue
    | PullRequestCardContent PullRequest


type alias ProjectLocation =
    { id : ID
    , url : String
    , name : String
    , number : Int
    }


type alias CardLocation =
    { id : ID
    , project : ProjectLocation
    , column : Maybe ProjectColumn
    }


type TimelineEvent
    = IssueCommentEvent (Maybe User) Date
    | CrossReferencedEvent ID


type alias OrgSelector =
    { name : String }


type alias RepoSelector =
    { owner : String, name : String }


type alias ProjectSelector =
    { owner : String, number : Int }


type alias IDSelector =
    { id : ID }


type alias IssueOrPRSelector =
    { owner : String, repo : String, number : Int }


type alias PagedSelector a =
    { selector : a, after : Maybe ID }


type alias PagedResult a =
    { content : List a
    , pageInfo : PageInfo
    }


type alias PageInfo =
    { endCursor : Maybe ID
    , hasNextPage : Bool
    }


fetchOrgRepos : Token -> OrgSelector -> Task Error (List Repo)
fetchOrgRepos token org =
    fetchPaged reposQuery token { selector = org, after = Nothing }


fetchOrgProjects : Token -> OrgSelector -> Task Error (List Project)
fetchOrgProjects token org =
    fetchPaged projectsQuery token { selector = org, after = Nothing }


fetchOrgProject : Token -> ProjectSelector -> Task Error Project
fetchOrgProject token project =
    projectQuery
        |> GB.request project
        |> GH.customSendQuery (authedOptions token)


fetchProjectColumnCards : Token -> IDSelector -> Task Error (List ProjectColumnCard)
fetchProjectColumnCards token col =
    fetchPaged cardsQuery token { selector = col, after = Nothing }


fetchRepo : Token -> RepoSelector -> Task Error Repo
fetchRepo token repo =
    repoQuery
        |> GB.request repo
        |> GH.customSendQuery (authedOptions token)


fetchRepoIssues : Token -> RepoSelector -> Task Error (List Issue)
fetchRepoIssues token repo =
    fetchPaged issuesQuery token { selector = repo, after = Nothing }


fetchRepoIssue : Token -> IssueOrPRSelector -> Task Error Issue
fetchRepoIssue token sel =
    issueQuery
        |> GB.request sel
        |> GH.customSendQuery (authedOptions token)


fetchRepoPullRequests : Token -> RepoSelector -> Task Error (List PullRequest)
fetchRepoPullRequests token repo =
    fetchPaged pullRequestsQuery token { selector = repo, after = Nothing }


fetchRepoPullRequest : Token -> IssueOrPRSelector -> Task Error PullRequest
fetchRepoPullRequest token sel =
    pullRequestQuery
        |> GB.request sel
        |> GH.customSendQuery (authedOptions token)


fetchTimeline : Token -> IDSelector -> Task Error (List TimelineEvent)
fetchTimeline token issue =
    fetchPaged timelineQuery token { selector = issue, after = Nothing }


moveCardAfter : Token -> ID -> ID -> Maybe ID -> Task Error ID
moveCardAfter token columnID cardID mafterID =
    moveCardMutation
        |> GB.request { columnId = columnID, cardId = cardID, afterId = mafterID }
        |> GH.customSendMutation (authedOptions token)


addContentCard : Token -> ID -> ID -> Task Error ID
addContentCard token columnID contentID =
    addCardMutation
        |> GB.request { columnId = columnID, contentId = contentID }
        |> GH.customSendMutation (authedOptions token)


addContentCardAfter : Token -> ID -> ID -> Maybe ID -> Task Error ID
addContentCardAfter token columnID contentID mafterID =
    addContentCard token columnID contentID
        |> Task.andThen (\cardID -> moveCardAfter token columnID cardID mafterID)


createRepoLabel : Token -> Repo -> String -> String -> Task Http.Error ()
createRepoLabel token repo name color =
    HttpBuilder.post ("https://api.github.com/repos/" ++ repo.owner ++ "/" ++ repo.name ++ "/labels")
        |> HttpBuilder.withHeaders (auth token)
        |> HttpBuilder.withJsonBody (encodeLabelPatch name color)
        |> HttpBuilder.toTask


deleteRepoLabel : Token -> Repo -> String -> Task Http.Error ()
deleteRepoLabel token repo name =
    HttpBuilder.delete ("https://api.github.com/repos/" ++ repo.owner ++ "/" ++ repo.name ++ "/labels/" ++ name)
        |> HttpBuilder.withHeaders (auth token)
        |> HttpBuilder.toTask


updateRepoLabel : Token -> Repo -> Label -> String -> String -> Task Http.Error ()
updateRepoLabel token repo label name color =
    HttpBuilder.patch ("https://api.github.com/repos/" ++ repo.owner ++ "/" ++ repo.name ++ "/labels/" ++ label.name)
        |> HttpBuilder.withHeaders (auth token)
        |> HttpBuilder.withJsonBody (encodeLabelPatch name color)
        |> HttpBuilder.toTask


createRepoMilestone : Token -> Repo -> String -> Task Http.Error ()
createRepoMilestone token repo title =
    HttpBuilder.post ("https://api.github.com/repos/" ++ repo.owner ++ "/" ++ repo.name ++ "/milestones")
        |> HttpBuilder.withHeaders (auth token)
        |> HttpBuilder.withJsonBody (JE.object [ ( "title", JE.string title ) ])
        |> HttpBuilder.toTask


closeRepoMilestone : Token -> Repo -> Milestone -> Task Http.Error ()
closeRepoMilestone token repo milestone =
    HttpBuilder.patch ("https://api.github.com/repos/" ++ repo.owner ++ "/" ++ repo.name ++ "/milestones/" ++ toString milestone.number)
        |> HttpBuilder.withHeaders (auth token)
        |> HttpBuilder.withJsonBody (JE.object [ ( "state", JE.string "closed" ) ])
        |> HttpBuilder.toTask


deleteRepoMilestone : Token -> Repo -> Milestone -> Task Http.Error ()
deleteRepoMilestone token repo milestone =
    HttpBuilder.delete ("https://api.github.com/repos/" ++ repo.owner ++ "/" ++ repo.name ++ "/milestones/" ++ toString milestone.number)
        |> HttpBuilder.withHeaders (auth token)
        |> HttpBuilder.toTask


closeIssue : Token -> Issue -> Task Http.Error ()
closeIssue token issue =
    HttpBuilder.patch ("https://api.github.com/repos" ++ issue.resourcePath)
        |> HttpBuilder.withHeaders (auth token)
        |> HttpBuilder.withJsonBody (JE.object [ ( "state", JE.string "closed" ) ])
        |> HttpBuilder.toTask


addIssueLabels : Token -> Issue -> List String -> Task Http.Error ()
addIssueLabels token issue names =
    HttpBuilder.post ("https://api.github.com/repos" ++ issue.resourcePath ++ "/labels")
        |> HttpBuilder.withHeaders (auth token)
        |> HttpBuilder.withJsonBody (JE.list (List.map JE.string names))
        |> HttpBuilder.toTask


removeIssueLabel : Token -> Issue -> String -> Task Http.Error ()
removeIssueLabel token issue name =
    HttpBuilder.delete ("https://api.github.com/repos" ++ issue.resourcePath ++ "/labels/" ++ name)
        |> HttpBuilder.withHeaders (auth token)
        |> HttpBuilder.toTask


encodeLabelPatch : String -> String -> JE.Value
encodeLabelPatch name color =
    JE.object
        [ ( "name", JE.string name )
        , ( "color", JE.string color )
        ]


moveCardMutation : GB.Document GB.Mutation ID { columnId : ID, cardId : ID, afterId : Maybe ID }
moveCardMutation =
    let
        columnIDVar =
            GV.required "columnId" .columnId GV.id

        cardIDVar =
            GV.required "cardId" .cardId GV.id

        afterIDVar =
            GV.required "afterId" .afterId (GV.nullable GV.id)
    in
        GB.mutationDocument <|
            GB.extract <|
                GB.field "moveProjectCard"
                    [ ( "input"
                      , GA.object
                            [ ( "columnId", GA.variable columnIDVar )
                            , ( "cardId", GA.variable cardIDVar )
                            , ( "afterCardId", GA.variable afterIDVar )
                            ]
                      )
                    ]
                    (GB.extract <|
                        GB.field "cardEdge"
                            []
                            (GB.extract <|
                                GB.field "node" [] (GB.extract <| GB.field "id" [] GB.id)
                            )
                    )


addCardMutation : GB.Document GB.Mutation ID { columnId : ID, contentId : ID }
addCardMutation =
    let
        columnIDVar =
            GV.required "columnId" .columnId GV.id

        contentIDVar =
            GV.required "contentId" .contentId GV.id
    in
        GB.mutationDocument <|
            GB.extract <|
                GB.field "addProjectCard"
                    [ ( "input"
                      , GA.object
                            [ ( "projectColumnId", GA.variable columnIDVar )
                            , ( "contentId", GA.variable contentIDVar )
                            ]
                      )
                    ]
                    (GB.extract <|
                        GB.field "cardEdge"
                            []
                            (GB.extract <|
                                GB.field "node" [] (GB.extract <| GB.field "id" [] GB.id)
                            )
                    )


issueScore : { a | reactions : Reactions, commentCount : Int } -> Int
issueScore { reactions, commentCount } =
    reactionScore reactions
        + (2 * commentCount)


pullRequestScore : { a | reactions : Reactions, commentCount : Int } -> Int
pullRequestScore { reactions, commentCount } =
    1000
        + reactionScore reactions
        + (2 * commentCount)


reactionScore : Reactions -> Int
reactionScore reactions =
    List.sum <|
        flip List.map reactions <|
            \{ type_, count } ->
                case type_ of
                    ReactionTypeThumbsUp ->
                        2 * count

                    ReactionTypeThumbsDown ->
                        -2 * count

                    ReactionTypeLaugh ->
                        count

                    ReactionTypeConfused ->
                        -count

                    ReactionTypeHeart ->
                        3 * count

                    ReactionTypeHooray ->
                        3 * count


labelEq : Label -> Label -> Bool
labelEq a b =
    a.name == b.name && String.toLower a.color == String.toLower b.color


auth : String -> List ( String, String )
auth token =
    if token == "" then
        []
    else
        [ ( "Authorization", "token " ++ token ) ]


authHeaders : String -> List Http.Header
authHeaders =
    List.map (uncurry Http.header) << auth


authedOptions : Token -> GH.RequestOptions
authedOptions token =
    { method = "POST"
    , headers = authHeaders token
    , url = "https://api.github.com/graphql"
    , timeout = Nothing
    , withCredentials = False
    }


fetchPaged : GB.Document GB.Query (PagedResult a) (PagedSelector s) -> Token -> PagedSelector s -> Task Error (List a)
fetchPaged doc token psel =
    let
        fetchNextPage { content, pageInfo } =
            if pageInfo.hasNextPage then
                fetchPaged doc token { psel | after = pageInfo.endCursor }
                    |> Task.map ((++) content)
            else
                Task.succeed content
    in
        doc
            |> GB.request psel
            |> GH.customSendQuery (authedOptions token)
            |> Task.andThen fetchNextPage


type DateType
    = DateType


issueStates : List ( String, IssueState )
issueStates =
    [ ( "OPEN", IssueStateOpen )
    , ( "CLOSED", IssueStateClosed )
    ]


pullRequestStates : List ( String, PullRequestState )
pullRequestStates =
    [ ( "OPEN", PullRequestStateOpen )
    , ( "CLOSED", PullRequestStateClosed )
    , ( "MERGED", PullRequestStateMerged )
    ]


milestoneStates : List ( String, MilestoneState )
milestoneStates =
    [ ( "OPEN", MilestoneStateOpen )
    , ( "CLOSED", MilestoneStateClosed )
    ]


reactionTypes : List ( String, ReactionType )
reactionTypes =
    [ ( "THUMBS_UP", ReactionTypeThumbsUp )
    , ( "THUMBS_DOWN", ReactionTypeThumbsDown )
    , ( "LAUGH", ReactionTypeLaugh )
    , ( "HOORAY", ReactionTypeHooray )
    , ( "CONFUSED", ReactionTypeConfused )
    , ( "HEART", ReactionTypeHeart )
    ]


repoObject : GB.ValueSpec GB.NonNull GB.ObjectType Repo vars
repoObject =
    GB.object Repo
        |> GB.with (GB.field "id" [] GB.string)
        |> GB.with (GB.field "url" [] GB.string)
        |> GB.with (GB.field "owner" [] (GB.extract (GB.field "login" [] GB.string)))
        |> GB.with (GB.field "name" [] GB.string)
        |> GB.with (GB.field "labels" [ ( "first", GA.int 100 ) ] (GB.extract <| GB.field "nodes" [] (GB.list labelObject)))
        |> GB.with (GB.field "milestones" [ ( "first", GA.int 100 ) ] (GB.extract <| GB.field "nodes" [] (GB.list milestoneObject)))


repoQuery : GB.Document GB.Query Repo RepoSelector
repoQuery =
    let
        ownerVar =
            GV.required "owner" .owner GV.string

        nameVar =
            GV.required "name" .name GV.string

        queryRoot =
            GB.extract <|
                GB.field "repository"
                    [ ( "owner", GA.variable ownerVar )
                    , ( "name", GA.variable nameVar )
                    ]
                    repoObject
    in
        GB.queryDocument queryRoot


reposQuery : GB.Document GB.Query (PagedResult Repo) (PagedSelector OrgSelector)
reposQuery =
    let
        orgNameVar =
            GV.required "orgName" (.name << .selector) GV.string

        afterVar =
            GV.required "after" .after (GV.nullable GV.string)

        pageArgs =
            [ ( "first", GA.int 100 )
            , ( "after", GA.variable afterVar )
            ]

        pageInfo =
            GB.object PageInfo
                |> GB.with (GB.field "endCursor" [] (GB.nullable GB.string))
                |> GB.with (GB.field "hasNextPage" [] GB.bool)

        paged =
            GB.object PagedResult
                |> GB.with (GB.field "nodes" [] (GB.list repoObject))
                |> GB.with (GB.field "pageInfo" [] pageInfo)

        queryRoot =
            GB.extract <|
                GB.field "organization"
                    [ ( "login", GA.variable orgNameVar )
                    ]
                <|
                    GB.extract (GB.field "repositories" pageArgs paged)
    in
        GB.queryDocument queryRoot


projectObject : GB.ValueSpec GB.NonNull GB.ObjectType Project vars
projectObject =
    GB.object Project
        |> GB.with (GB.field "id" [] GB.string)
        |> GB.with (GB.field "url" [] GB.string)
        |> GB.with (GB.field "name" [] GB.string)
        |> GB.with (GB.field "number" [] GB.int)
        |> GB.with (GB.field "columns" [ ( "first", GA.int 50 ) ] (GB.extract (GB.field "nodes" [] (GB.list columnObject))))


projectQuery : GB.Document GB.Query Project ProjectSelector
projectQuery =
    let
        orgNameVar =
            GV.required "orgName" .owner GV.string

        projectNumberVar =
            GV.required "projectNumber" .number GV.int

        queryRoot =
            GB.extract <|
                GB.field "organization"
                    [ ( "login", GA.variable orgNameVar )
                    ]
                <|
                    GB.extract (GB.field "project" [ ( "number", GA.variable projectNumberVar ) ] projectObject)
    in
        GB.queryDocument queryRoot


projectsQuery : GB.Document GB.Query (PagedResult Project) (PagedSelector OrgSelector)
projectsQuery =
    let
        orgNameVar =
            GV.required "orgName" (.name << .selector) GV.string

        afterVar =
            GV.required "after" .after (GV.nullable GV.string)

        pageArgs =
            [ ( "first", GA.int 100 )
            , ( "after", GA.variable afterVar )
            ]

        pageInfo =
            GB.object PageInfo
                |> GB.with (GB.field "endCursor" [] (GB.nullable GB.string))
                |> GB.with (GB.field "hasNextPage" [] GB.bool)

        paged =
            GB.object PagedResult
                |> GB.with (GB.field "nodes" [] (GB.list projectObject))
                |> GB.with (GB.field "pageInfo" [] pageInfo)

        queryRoot =
            GB.extract <|
                GB.field "organization"
                    [ ( "login", GA.variable orgNameVar )
                    ]
                <|
                    GB.extract (GB.field "projects" pageArgs paged)
    in
        GB.queryDocument queryRoot


cardsQuery : GB.Document GB.Query (PagedResult ProjectColumnCard) (PagedSelector IDSelector)
cardsQuery =
    let
        idVar =
            GV.required "id" (.id << .selector) GV.id

        afterVar =
            GV.required "after" .after (GV.nullable GV.string)

        content =
            GB.object pickEnum2
                |> GB.with (GB.inlineFragment (Just (GB.onType "Issue")) (GB.map IssueCardContent issueObject))
                |> GB.with (GB.inlineFragment (Just (GB.onType "PullRequest")) (GB.map PullRequestCardContent prObject))

        card =
            GB.object ProjectColumnCard
                |> GB.with (GB.field "id" [] GB.string)
                |> GB.with (GB.field "content" [] content)
                |> GB.with (GB.field "note" [] (GB.nullable GB.string))

        pageArgs =
            [ ( "first", GA.int 100 )
            , ( "after", GA.variable afterVar )
            ]

        pageInfo =
            GB.object PageInfo
                |> GB.with (GB.field "endCursor" [] (GB.nullable GB.string))
                |> GB.with (GB.field "hasNextPage" [] GB.bool)

        paged =
            GB.object PagedResult
                |> GB.with (GB.field "nodes" [] (GB.list card))
                |> GB.with (GB.field "pageInfo" [] pageInfo)

        cards =
            (GB.extract (GB.field "cards" pageArgs paged))

        queryRoot =
            GB.extract <|
                GB.assume <|
                    GB.field "node"
                        [ ( "id", GA.variable idVar )
                        ]
                        (GB.extract <| GB.inlineFragment (Just <| GB.onType "ProjectColumn") cards)
    in
        GB.queryDocument queryRoot


projectLocationObject : GB.ValueSpec GB.NonNull GB.ObjectType ProjectLocation vars
projectLocationObject =
    GB.object ProjectLocation
        |> GB.with (GB.field "id" [] GB.string)
        |> GB.with (GB.field "url" [] GB.string)
        |> GB.with (GB.field "name" [] GB.string)
        |> GB.with (GB.field "number" [] GB.int)


labelObject : GB.ValueSpec GB.NonNull GB.ObjectType Label vars
labelObject =
    GB.object Label
        |> GB.with (GB.field "id" [] GB.string)
        |> GB.with (GB.field "name" [] GB.string)
        |> GB.with (GB.field "color" [] GB.string)


milestoneObject : GB.ValueSpec GB.NonNull GB.ObjectType Milestone vars
milestoneObject =
    GB.object Milestone
        |> GB.with (GB.field "id" [] GB.string)
        |> GB.with (GB.field "number" [] GB.int)
        |> GB.with (GB.field "title" [] GB.string)
        |> GB.with (GB.field "state" [] (GB.enum milestoneStates))
        |> GB.with (GB.field "description" [] (GB.nullable GB.string))


columnObject : GB.ValueSpec GB.NonNull GB.ObjectType ProjectColumn vars
columnObject =
    GB.object ProjectColumn
        |> GB.with (GB.field "id" [] GB.string)
        |> GB.with (GB.field "name" [] GB.string)
        |> GB.with (GB.field "databaseId" [] GB.int)


authorObject : GB.SelectionSpec GB.InlineFragment User vars
authorObject =
    GB.assume
        (GB.inlineFragment (Just <| GB.onType "User")
            (GB.object User
                |> GB.with (GB.field "id" [] GB.string)
                |> GB.with (GB.field "url" [] GB.string)
                |> GB.with (GB.field "login" [] GB.string)
                |> GB.with (GB.field "avatarUrl" [] GB.string)
            )
        )


projectCardObject : GB.ValueSpec GB.NonNull GB.ObjectType CardLocation vars
projectCardObject =
    GB.object CardLocation
        |> GB.with (GB.field "id" [] GB.string)
        |> GB.with (GB.field "project" [] projectLocationObject)
        |> GB.with (GB.field "column" [] (GB.nullable columnObject))


reactionGroupObject : GB.ValueSpec GB.NonNull GB.ObjectType ReactionGroup vars
reactionGroupObject =
    GB.object ReactionGroup
        |> GB.with (GB.field "content" [] (GB.enum reactionTypes))
        |> GB.with (GB.field "users" [] (GB.extract (GB.field "totalCount" [] GB.int)))


issueObject : GB.ValueSpec GB.NonNull GB.ObjectType Issue vars
issueObject =
    GB.object Issue
        |> GB.with (GB.field "id" [] GB.string)
        |> GB.with (GB.field "url" [] GB.string)
        |> GB.with (GB.field "resourcePath" [] GB.string)
        |> GB.with (GB.field "createdAt" [] (GB.customScalar DateType JDE.date))
        |> GB.with (GB.field "updatedAt" [] (GB.customScalar DateType JDE.date))
        |> GB.with (GB.aliasAs "issueState" <| GB.field "state" [] (GB.enum issueStates))
        |> GB.with (GB.field "number" [] GB.int)
        |> GB.with (GB.field "title" [] GB.string)
        |> GB.with (GB.field "comments" [] (GB.extract (GB.field "totalCount" [] GB.int)))
        |> GB.with (GB.field "reactionGroups" [] (GB.list reactionGroupObject))
        |> GB.with (GB.field "author" [] (GB.nullable (GB.extract authorObject)))
        |> GB.with (GB.field "labels" [ ( "first", GA.int 10 ) ] (GB.extract <| GB.field "nodes" [] (GB.list labelObject)))
        |> GB.with (GB.field "projectCards" [ ( "first", GA.int 10 ) ] (GB.extract <| GB.field "nodes" [] (GB.list projectCardObject)))
        |> GB.with (GB.field "milestone" [] (GB.nullable milestoneObject))


prObject : GB.ValueSpec GB.NonNull GB.ObjectType PullRequest vars
prObject =
    GB.object PullRequest
        |> GB.with (GB.field "id" [] GB.string)
        |> GB.with (GB.field "url" [] GB.string)
        |> GB.with (GB.field "createdAt" [] (GB.customScalar DateType JDE.date))
        |> GB.with (GB.field "updatedAt" [] (GB.customScalar DateType JDE.date))
        |> GB.with (GB.aliasAs "prState" <| GB.field "state" [] (GB.enum pullRequestStates))
        |> GB.with (GB.field "number" [] GB.int)
        |> GB.with (GB.field "title" [] GB.string)
        |> GB.with (GB.field "comments" [] (GB.extract (GB.field "totalCount" [] GB.int)))
        |> GB.with (GB.field "reactionGroups" [] (GB.list reactionGroupObject))
        |> GB.with (GB.field "author" [] (GB.nullable (GB.extract authorObject)))
        |> GB.with (GB.field "labels" [ ( "first", GA.int 10 ) ] (GB.extract <| GB.field "nodes" [] (GB.list labelObject)))
        |> GB.with (GB.field "projectCards" [ ( "first", GA.int 10 ) ] (GB.extract <| GB.field "nodes" [] (GB.list projectCardObject)))
        |> GB.with (GB.field "additions" [] GB.int)
        |> GB.with (GB.field "deletions" [] GB.int)
        |> GB.with (GB.field "milestone" [] (GB.nullable milestoneObject))


issuesQuery : GB.Document GB.Query (PagedResult Issue) (PagedSelector RepoSelector)
issuesQuery =
    let
        orgNameVar =
            GV.required "orgName" (.owner << .selector) GV.string

        repoNameVar =
            GV.required "repoName" (.name << .selector) GV.string

        afterVar =
            GV.required "after" .after (GV.nullable GV.string)

        pageArgs =
            [ ( "first", GA.int 100 )
            , ( "states", GA.list [ GA.enum "OPEN" ] )
            , ( "after", GA.variable afterVar )
            ]

        pageInfo =
            GB.object PageInfo
                |> GB.with (GB.field "endCursor" [] (GB.nullable GB.string))
                |> GB.with (GB.field "hasNextPage" [] GB.bool)

        paged =
            GB.object PagedResult
                |> GB.with (GB.field "nodes" [] (GB.list issueObject))
                |> GB.with (GB.field "pageInfo" [] pageInfo)

        queryRoot =
            GB.extract <|
                GB.field "repository"
                    [ ( "owner", GA.variable orgNameVar )
                    , ( "name", GA.variable repoNameVar )
                    ]
                <|
                    GB.extract (GB.field "issues" pageArgs paged)
    in
        GB.queryDocument queryRoot


issueQuery : GB.Document GB.Query Issue IssueOrPRSelector
issueQuery =
    let
        orgNameVar =
            GV.required "orgName" .owner GV.string

        repoNameVar =
            GV.required "repoName" .repo GV.string

        numberVar =
            GV.required "number" .number GV.int

        queryRoot =
            GB.extract <|
                GB.field "repository"
                    [ ( "owner", GA.variable orgNameVar )
                    , ( "name", GA.variable repoNameVar )
                    ]
                <|
                    GB.extract (GB.field "issue" [ ( "number", GA.variable numberVar ) ] issueObject)
    in
        GB.queryDocument queryRoot


pullRequestsQuery : GB.Document GB.Query (PagedResult PullRequest) (PagedSelector RepoSelector)
pullRequestsQuery =
    let
        orgNameVar =
            GV.required "orgName" (.owner << .selector) GV.string

        repoNameVar =
            GV.required "repoName" (.name << .selector) GV.string

        afterVar =
            GV.required "after" .after (GV.nullable GV.string)

        pageArgs =
            [ ( "first", GA.int 100 )
            , ( "states", GA.list [ GA.enum "OPEN" ] )
            , ( "after", GA.variable afterVar )
            ]

        pageInfo =
            GB.object PageInfo
                |> GB.with (GB.field "endCursor" [] (GB.nullable GB.string))
                |> GB.with (GB.field "hasNextPage" [] GB.bool)

        paged =
            GB.object PagedResult
                |> GB.with (GB.field "nodes" [] (GB.list prObject))
                |> GB.with (GB.field "pageInfo" [] pageInfo)

        queryRoot =
            GB.extract <|
                GB.field "repository"
                    [ ( "owner", GA.variable orgNameVar )
                    , ( "name", GA.variable repoNameVar )
                    ]
                <|
                    GB.extract (GB.field "pullRequests" pageArgs paged)
    in
        GB.queryDocument queryRoot


pullRequestQuery : GB.Document GB.Query PullRequest IssueOrPRSelector
pullRequestQuery =
    let
        orgNameVar =
            GV.required "orgName" .owner GV.string

        repoNameVar =
            GV.required "repoName" .repo GV.string

        numberVar =
            GV.required "number" .number GV.int

        queryRoot =
            GB.extract <|
                GB.field "repository"
                    [ ( "owner", GA.variable orgNameVar )
                    , ( "name", GA.variable repoNameVar )
                    ]
                <|
                    GB.extract (GB.field "pullRequest" [ ( "number", GA.variable numberVar ) ] prObject)
    in
        GB.queryDocument queryRoot


timelineQuery : GB.Document GB.Query (PagedResult TimelineEvent) (PagedSelector IDSelector)
timelineQuery =
    let
        issueIdVar =
            GV.required "issueId" (.id << .selector) GV.id

        afterVar =
            GV.required "after" .after (GV.nullable GV.string)

        issueCommentEvent =
            GB.object IssueCommentEvent
                |> GB.with (GB.field "author" [] (GB.nullable (GB.extract authorObject)))
                |> GB.with (GB.field "createdAt" [] (GB.customScalar DateType JDE.date))

        sourceID =
            GB.object pickEnum2
                |> GB.with (GB.inlineFragment (Just (GB.onType "Issue")) (GB.extract <| GB.field "id" [] GB.string))
                |> GB.with (GB.inlineFragment (Just (GB.onType "PullRequest")) (GB.extract <| GB.field "id" [] GB.string))

        crossReferencedEvent =
            GB.object CrossReferencedEvent
                |> GB.with (GB.assume <| GB.field "source" [] sourceID)

        event =
            GB.object pickEnum2
                |> GB.with (GB.inlineFragment (Just (GB.onType "IssueComment")) issueCommentEvent)
                |> GB.with (GB.inlineFragment (Just (GB.onType "CrossReferencedEvent")) crossReferencedEvent)

        pageArgs =
            [ ( "first", GA.int 100 )
            , ( "after", GA.variable afterVar )
            ]

        pageInfo =
            GB.object PageInfo
                |> GB.with (GB.field "endCursor" [] (GB.nullable GB.string))
                |> GB.with (GB.field "hasNextPage" [] GB.bool)

        paged =
            GB.object PagedResult
                |> GB.with (GB.field "nodes" [] (GB.map (List.filterMap identity) (GB.list event)))
                |> GB.with (GB.field "pageInfo" [] pageInfo)

        timeline =
            (GB.extract (GB.field "timeline" pageArgs paged))

        issueOrPRTimeline =
            GB.object pickEnum2
                |> GB.with (GB.inlineFragment (Just <| GB.onType "Issue") timeline)
                |> GB.with (GB.inlineFragment (Just <| GB.onType "PullRequest") timeline)

        queryRoot =
            GB.extract <|
                GB.assume <|
                    GB.field "node"
                        [ ( "id", GA.variable issueIdVar )
                        ]
                        issueOrPRTimeline
    in
        GB.queryDocument queryRoot


pickEnum2 : Maybe a -> Maybe a -> Maybe a
pickEnum2 ma mb =
    case ma of
        Just x ->
            Just x

        _ ->
            mb


decodeRepo : JD.Decoder Repo
decodeRepo =
    JD.succeed Repo
        |: (JD.field "id" JD.string)
        |: (JD.field "url" JD.string)
        |: (JD.field "owner" JD.string)
        |: (JD.field "name" JD.string)
        |: (JD.field "labels" (JD.list decodeLabel))
        |: (JD.field "milestones" (JD.list decodeMilestone))


decodeIssue : JD.Decoder Issue
decodeIssue =
    JD.succeed Issue
        |: (JD.field "id" JD.string)
        |: (JD.field "url" JD.string)
        |: (JD.field "resource_path" JD.string)
        |: (JD.field "created_at" JDE.date)
        |: (JD.field "updated_at" JDE.date)
        |: (JD.field "state" decodeIssueState)
        |: (JD.field "number" JD.int)
        |: (JD.field "title" JD.string)
        |: (JD.field "comment_count" JD.int)
        |: (JD.field "reactions" <| JD.list decodeReactionGroup)
        |: (JD.field "author" (JD.maybe decodeUser))
        |: (JD.field "labels" <| JD.list decodeLabel)
        |: (JD.field "cards" <| JD.list decodeCardLocation)
        |: (JD.field "milestone" <| JD.maybe decodeMilestone)


decodePullRequest : JD.Decoder PullRequest
decodePullRequest =
    JD.succeed PullRequest
        |: (JD.field "id" JD.string)
        |: (JD.field "url" JD.string)
        |: (JD.field "created_at" JDE.date)
        |: (JD.field "updated_at" JDE.date)
        |: (JD.field "state" decodePullRequestState)
        |: (JD.field "number" JD.int)
        |: (JD.field "title" JD.string)
        |: (JD.field "comment_count" JD.int)
        |: (JD.field "reactions" <| JD.list decodeReactionGroup)
        |: (JD.field "author" (JD.maybe decodeUser))
        |: (JD.field "labels" <| JD.list decodeLabel)
        |: (JD.field "cards" <| JD.list decodeCardLocation)
        |: (JD.field "additions" JD.int)
        |: (JD.field "deletions" JD.int)
        |: (JD.field "milestone" <| JD.maybe decodeMilestone)


decodeLabel : JD.Decoder Label
decodeLabel =
    JD.succeed Label
        |: (JD.field "id" JD.string)
        |: (JD.field "name" JD.string)
        |: (JD.field "color" JD.string)


decodeMilestone : JD.Decoder Milestone
decodeMilestone =
    JD.succeed Milestone
        |: (JD.field "id" JD.string)
        |: (JD.field "number" JD.int)
        |: (JD.field "title" JD.string)
        |: (JD.field "state" decodeMilestoneState)
        |: (JD.field "description" (JD.maybe JD.string))


decodeReactionGroup : JD.Decoder ReactionGroup
decodeReactionGroup =
    JD.succeed ReactionGroup
        |: (JD.field "type_" decodeReactionType)
        |: (JD.field "count" JD.int)


decodeReactionType : JD.Decoder ReactionType
decodeReactionType =
    let
        decodeToType string =
            case Dict.get string (Dict.fromList reactionTypes) of
                Just type_ ->
                    Result.Ok type_

                Nothing ->
                    Result.Err ("Not valid pattern for decoder to ReactionType. Pattern: " ++ (toString string))
    in
        customDecoder JD.string decodeToType


decodeMilestoneState : JD.Decoder MilestoneState
decodeMilestoneState =
    let
        decodeToType string =
            case Dict.get string (Dict.fromList milestoneStates) of
                Just type_ ->
                    Result.Ok type_

                Nothing ->
                    Result.Err ("Not valid pattern for decoder to MilestoneState. Pattern: " ++ (toString string))
    in
        customDecoder JD.string decodeToType


decodeUser : JD.Decoder User
decodeUser =
    JD.succeed User
        |: (JD.field "id" JD.string)
        |: (JD.field "url" JD.string)
        |: (JD.field "login" JD.string)
        |: (JD.field "avatar" JD.string)


decodeProject : JD.Decoder Project
decodeProject =
    JD.succeed Project
        |: (JD.field "id" JD.string)
        |: (JD.field "url" JD.string)
        |: (JD.field "name" JD.string)
        |: (JD.field "number" JD.int)
        |: (JD.field "columns" <| JD.list decodeProjectColumn)


decodeProjectLocation : JD.Decoder ProjectLocation
decodeProjectLocation =
    JD.succeed ProjectLocation
        |: (JD.field "id" JD.string)
        |: (JD.field "url" JD.string)
        |: (JD.field "name" JD.string)
        |: (JD.field "number" JD.int)


decodeProjectColumn : JD.Decoder ProjectColumn
decodeProjectColumn =
    JD.succeed ProjectColumn
        |: (JD.field "id" JD.string)
        |: (JD.field "name" JD.string)
        |: (JD.field "database_id" JD.int)


decodeProjectColumnCard : JD.Decoder ProjectColumnCard
decodeProjectColumnCard =
    JD.succeed ProjectColumnCard
        |: (JD.field "id" JD.string)
        |: (JD.field "content" <| JD.maybe decodeCardContent)
        |: (JD.field "note" <| JD.maybe JD.string)


decodeCardContent : JD.Decoder CardContent
decodeCardContent =
    JD.oneOf
        [ JD.field "issue" (JD.map IssueCardContent decodeIssue)
        , JD.field "pull_request" (JD.map PullRequestCardContent decodePullRequest)
        ]


decodeCardLocation : JD.Decoder CardLocation
decodeCardLocation =
    JD.succeed CardLocation
        |: (JD.field "id" JD.string)
        |: (JD.field "project" decodeProjectLocation)
        |: (JD.field "column" <| JD.maybe decodeProjectColumn)


decodeRepoSelector : JD.Decoder RepoSelector
decodeRepoSelector =
    JD.succeed RepoSelector
        |: (JD.field "owner" JD.string)
        |: (JD.field "name" JD.string)


decodeOrgSelector : JD.Decoder OrgSelector
decodeOrgSelector =
    JD.succeed OrgSelector
        |: (JD.field "name" JD.string)


decodePullRequestState : JD.Decoder PullRequestState
decodePullRequestState =
    let
        decodeToType string =
            case Dict.get string (Dict.fromList pullRequestStates) of
                Just type_ ->
                    Result.Ok type_

                Nothing ->
                    Result.Err ("Not valid pattern for decoder to PullRequestState. Pattern: " ++ (toString string))
    in
        customDecoder JD.string decodeToType


decodeIssueState : JD.Decoder IssueState
decodeIssueState =
    let
        decodeToType string =
            case Dict.get string (Dict.fromList issueStates) of
                Just type_ ->
                    Result.Ok type_

                Nothing ->
                    Result.Err ("Not valid pattern for decoder to IssueState. Pattern: " ++ (toString string))
    in
        customDecoder JD.string decodeToType


encodeRepo : Repo -> JE.Value
encodeRepo record =
    JE.object
        [ ( "id", JE.string record.id )
        , ( "url", JE.string record.url )
        , ( "owner", JE.string record.owner )
        , ( "name", JE.string record.name )
        , ( "labels", JE.list (List.map encodeLabel record.labels) )
        , ( "milestones", JE.list (List.map encodeMilestone record.milestones) )
        ]


encodeIssue : Issue -> JE.Value
encodeIssue record =
    JE.object
        [ ( "id", JE.string record.id )
        , ( "url", JE.string record.url )
        , ( "resource_path", JE.string record.resourcePath )
        , ( "created_at", JE.string (Date.Format.formatISO8601 record.createdAt) )
        , ( "updated_at", JE.string (Date.Format.formatISO8601 record.updatedAt) )
        , ( "state", encodeIssueState record.state )
        , ( "number", JE.int record.number )
        , ( "title", JE.string record.title )
        , ( "comment_count", JE.int record.commentCount )
        , ( "reactions", JE.list (List.map encodeReactionGroup record.reactions) )
        , ( "author", JEE.maybe encodeUser record.author )
        , ( "labels", JE.list <| List.map encodeLabel record.labels )
        , ( "cards", JE.list <| List.map encodeCardLocation record.cards )
        , ( "milestone", JEE.maybe encodeMilestone record.milestone )
        ]


encodePullRequest : PullRequest -> JE.Value
encodePullRequest record =
    JE.object
        [ ( "id", JE.string record.id )
        , ( "url", JE.string record.url )
        , ( "created_at", JE.string (Date.Format.formatISO8601 record.createdAt) )
        , ( "updated_at", JE.string (Date.Format.formatISO8601 record.updatedAt) )
        , ( "state", encodePullRequestState record.state )
        , ( "number", JE.int record.number )
        , ( "title", JE.string record.title )
        , ( "comment_count", JE.int record.commentCount )
        , ( "reactions", JE.list (List.map encodeReactionGroup record.reactions) )
        , ( "author", JEE.maybe encodeUser record.author )
        , ( "labels", JE.list <| List.map encodeLabel record.labels )
        , ( "cards", JE.list <| List.map encodeCardLocation record.cards )
        , ( "additions", JE.int record.additions )
        , ( "deletions", JE.int record.deletions )
        , ( "milestone", JEE.maybe encodeMilestone record.milestone )
        ]


encodeLabel : Label -> JE.Value
encodeLabel record =
    JE.object
        [ ( "id", JE.string record.id )
        , ( "name", JE.string record.name )
        , ( "color", JE.string record.color )
        ]


encodeMilestone : Milestone -> JE.Value
encodeMilestone record =
    JE.object
        [ ( "id", JE.string record.id )
        , ( "number", JE.int record.number )
        , ( "title", JE.string record.title )
        , ( "state", encodeMilestoneState record.state )
        , ( "description", JEE.maybe JE.string record.description )
        ]


encodeMilestoneState : MilestoneState -> JE.Value
encodeMilestoneState item =
    JE.string <|
        List.foldl
            (\( a, b ) default ->
                if b == item then
                    a
                else
                    default
            )
            "UNKNOWN"
            milestoneStates


encodeReactionGroup : ReactionGroup -> JE.Value
encodeReactionGroup record =
    JE.object
        [ ( "type_", encodeReactionType record.type_ )
        , ( "count", JE.int record.count )
        ]


encodeReactionType : ReactionType -> JE.Value
encodeReactionType item =
    JE.string <|
        List.foldl
            (\( a, b ) default ->
                if b == item then
                    a
                else
                    default
            )
            "UNKNOWN"
            reactionTypes


encodeUser : User -> JE.Value
encodeUser record =
    JE.object
        [ ( "id", JE.string record.id )
        , ( "url", JE.string record.url )
        , ( "login", JE.string record.login )
        , ( "avatar", JE.string record.avatar )
        ]


encodeProject : Project -> JE.Value
encodeProject record =
    JE.object
        [ ( "id", JE.string record.id )
        , ( "url", JE.string record.url )
        , ( "name", JE.string record.name )
        , ( "number", JE.int record.number )
        , ( "columns", JE.list <| List.map encodeProjectColumn record.columns )
        ]


encodeProjectLocation : ProjectLocation -> JE.Value
encodeProjectLocation record =
    JE.object
        [ ( "id", JE.string record.id )
        , ( "url", JE.string record.url )
        , ( "name", JE.string record.name )
        , ( "number", JE.int record.number )
        ]


encodeProjectColumn : ProjectColumn -> JE.Value
encodeProjectColumn record =
    JE.object
        [ ( "id", JE.string record.id )
        , ( "name", JE.string record.name )
        , ( "database_id", JE.int record.databaseId )
        ]


encodeProjectColumnCard : ProjectColumnCard -> JE.Value
encodeProjectColumnCard record =
    JE.object
        [ ( "id", JE.string record.id )
        , ( "content"
          , case record.content of
                Just (IssueCardContent issue) ->
                    JE.object [ ( "issue", encodeIssue issue ) ]

                Just (PullRequestCardContent pr) ->
                    JE.object [ ( "pull_request", encodePullRequest pr ) ]

                Nothing ->
                    JE.null
          )
        , ( "note", JEE.maybe JE.string record.note )
        ]


encodeCardLocation : CardLocation -> JE.Value
encodeCardLocation record =
    JE.object
        [ ( "id", JE.string record.id )
        , ( "project", encodeProjectLocation record.project )
        , ( "column", JEE.maybe encodeProjectColumn record.column )
        ]


encodeRepoSelector : RepoSelector -> JE.Value
encodeRepoSelector record =
    JE.object
        [ ( "owner", JE.string record.owner )
        , ( "name", JE.string record.name )
        ]


encodeOrgSelector : OrgSelector -> JE.Value
encodeOrgSelector record =
    JE.object
        [ ( "name", JE.string record.name )
        ]


encodeIssueState : IssueState -> JE.Value
encodeIssueState item =
    JE.string <|
        List.foldl
            (\( a, b ) default ->
                if b == item then
                    a
                else
                    default
            )
            "UNKNOWN"
            issueStates


encodePullRequestState : PullRequestState -> JE.Value
encodePullRequestState item =
    JE.string <|
        List.foldl
            (\( a, b ) default ->
                if b == item then
                    a
                else
                    default
            )
            "UNKNOWN"
            pullRequestStates


customDecoder : JD.Decoder b -> (b -> Result String a) -> JD.Decoder a
customDecoder decoder toResult =
    JD.andThen
        (\a ->
            case toResult a of
                Ok b ->
                    JD.succeed b

                Err err ->
                    JD.fail err
        )
        decoder
