import { Context, createContext, createSignal, createEffect } from "solid-js";
import { Title } from "../types/titles";
import { Mode, SearchType, Settings } from "../types/settings";

export const SettingsContext = createContext() as Context<Settings>;

export function SettingsProvider(props: { children: any }) {
  const [mode, setMode] = createSignal<Mode>(Mode.none);
  const [titles, setTitles] = createSignal<Title[]>([]);
  const [currentTitle, setCurrentTitle] = createSignal<Title | undefined>();
  const [isDub, setIsDub] = createSignal<boolean>(false);
  const [episodeNumber, setEpisodeNumber] = createSignal<string | undefined>();
  // searching
  const [searchTerm, setSearchTerm] = createSignal<string | undefined>();
  const [searchType, setSearchType] = createSignal<SearchType | undefined>();

  const updateLocalStorage = (settings: any) => {
    localStorage.setItem("settings", JSON.stringify(settings));
  };

  createEffect(() => {
    if (mode() != Mode.none) {
      const settings = {
        mode: mode(),
        titles: titles(),
        currentTitle: currentTitle(),
        isDub: isDub(),
        episodeNumber: episodeNumber(),
        searchTerm: searchTerm(),
      };
      updateLocalStorage(settings);
    }
  });

  createEffect(() => {
    const savedSettings = localStorage.getItem("settings");
    if (savedSettings) {
      const parsedSettings = JSON.parse(savedSettings);
      setMode(parsedSettings.mode);
      setTitles(parsedSettings.titles);
      setCurrentTitle(parsedSettings.currentTitle);
      setIsDub(parsedSettings.isDub);
      setEpisodeNumber(parsedSettings.episodeNumber);
      setSearchTerm(parsedSettings.searchTerm);
    }
  }, []);

  return (
    <SettingsContext.Provider
      value={{
        mode,
        setMode,
        titles,
        setTitles,
        currentTitle,
        setCurrentTitle,
        isDub,
        setIsDub,
        episodeNumber,
        setEpisodeNumber,
        searchTerm,
        setSearchTerm,
        searchType,
        setSearchType,
      }}
    >
      {props.children}
    </SettingsContext.Provider>
  );
}
