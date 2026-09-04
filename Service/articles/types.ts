export type CoverStyle = "mountain" | "river" | "seal";

export type SortMode = "latest" | "likes" | "dislikes" | "score";

export type Article = {
  id: string;
  title: string;
  category: string;
  tags: string[];
  cover: CoverStyle;
  coverUrl?: string;
  content: string;
  likes: number;
  dislikes: number;
  createdAt?: string;
  updatedAt?: string;
};

export type ArticleInput = {
  title: string;
  category: string;
  tags: string[];
  coverUrl?: string;
  content: string;
};

export type ArticleListOptions = {
  search?: string;
  category?: string;
  sort?: SortMode;
};

export type VoteType = "likes" | "dislikes";
