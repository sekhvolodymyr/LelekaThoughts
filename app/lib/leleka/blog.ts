export type Article={id:string;author_id:string;title:string;excerpt:string;body:string;status:'draft'|'published';created_at:string;updated_at:string;published_at:string|null;author?:{display_name:string;username:string}|null};
export const articleUrl=(id:string)=>`/blog/${id}`;
