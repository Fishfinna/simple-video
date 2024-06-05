import {
  For,
  Show,
  createEffect,
  createSignal,
  onMount,
  useContext,
} from "solid-js";
import { SettingsContext } from "../../context/settingsContext";
import { useNavigate } from "@solidjs/router";
import { Mode, SearchType } from "../../types/settings";
import {
  client,
  searchQuery,
  newQuery,
  randomQuery,
  popularQuery,
} from "../../api";
import { Icon } from "../Icons/icon";

import "./results.scss";

export function Results() {
  const {
    mode,
    setMode,
    titles,
    setTitles,
    setCurrentTitle,
    searchTerm,
    setSearchTerm,
    setEpisodeNumber,
    searchType,
  } = useContext(SettingsContext);
  const [page, setPage] = createSignal<number>(1);
  const [hasNextPage, setHasNextPage] = createSignal<boolean>(false);
  const [isLoading, setIsLoading] = createSignal<boolean>(false);
  const [error, setError] = createSignal<string | null>(null);
  const navigate = useNavigate();

  async function search(searchFunction: any, searchQuery?: string) {
    setIsLoading(true);
    setEpisodeNumber("1");
    const { query, variables } = searchQuery
      ? searchFunction(searchQuery, page())
      : searchFunction(page());
    try {
      const { data } = await client.query(query, variables).toPromise();
      if (data.shows.edges.length === 0) {
        throw new Error("No search results.");
      }
      setTitles(data.shows.edges);
      setCurrentTitle(undefined);
      setMode(Mode.title);
      setError(null);
    } catch (err: any) {
      setError(err.message);
    } finally {
      setIsLoading(false);
    }
  }

  onMount(() => {
    setPage(1);
    setHasNextPage(false);
  });

  createEffect(async () => {
    if (searchTerm()) {
      setPage(1);
      setHasNextPage(false);
    }
  }, [searchTerm]);

  createEffect(async () => {
    // load titles
    setTitles([]);
    setError(null);
    if (searchType() == SearchType.text) {
      // TODO refactor
      if (searchTerm()?.trim() != "" && searchTerm()) {
        setIsLoading(true);
        setEpisodeNumber("1");
        const { query, variables } = searchQuery(`${searchTerm()}`, page());
        try {
          const { data: response } = await client
            .query(query, variables)
            .toPromise();
          if (response.shows.edges.length === 0) {
            throw new Error("No search results.");
          }
          setTitles(response.shows.edges);
          setCurrentTitle(undefined);
          setMode(Mode.title);
          setError(null);
        } catch (err: any) {
          setError(err.message);
        } finally {
          setIsLoading(false);
        }
        // for navigation
        const { query: navQuery, variables: navVar } = searchQuery(
          `${searchTerm()}`,
          page() + 1
        );
        const { data } = await client.query(navQuery, navVar).toPromise();
        setHasNextPage(data.shows.edges.length !== 0);
      } else if (!searchTerm()) {
        setError(null);
        if (mode() == Mode.title) setMode(Mode.none);
      }
    } else if (searchType() == SearchType.popular) {
      console.log("popular");
      const { query, variables } = await popularQuery();
      try {
        const { data } = await client.query(query, variables).toPromise();
      } catch {}
    } else if (searchType() == SearchType.new) {
      console.log("new");
      setHasNextPage(false);
    } else if (searchType() == SearchType.random) {
      console.log("random");
      setHasNextPage(false);
    }
  }, [page]);

  return (
    <Show when={mode() === Mode.title}>
      <Show when={error()}>
        <div class="error">{error()}</div>
      </Show>
      <Show when={isLoading()}>
        <div class="loader"></div>
      </Show>

      <div class="results-container">
        <For each={titles()}>
          {(title) => (
            <div
              class="title"
              onClick={() => {
                setCurrentTitle(title);
                setMode(Mode.episode);
                setSearchTerm("");
                navigate(`/anime/${title._id}`);
              }}
            >
              <img src={title.thumbnail} />
              <h3 class="thumbnail-title">{title.englishName || title.name}</h3>
            </div>
          )}
        </For>
      </div>
      <Show when={page() != 1 || hasNextPage()}>
        <div class="page-control">
          <button disabled={page() == 1}>
            <Icon name="chevron_left" onClick={() => setPage(page() - 1)} />
          </button>
          <p class="page-control-block">|</p>
          <p class="current-page">page {page()}</p>
          <p class="page-control-block">|</p>
          <button disabled={!hasNextPage()}>
            <Icon name="chevron_right" onClick={() => setPage(page() + 1)} />
          </button>
        </div>
      </Show>
    </Show>
  );
}
