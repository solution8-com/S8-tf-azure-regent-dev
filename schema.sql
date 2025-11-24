-- PostgreSQL schema for Haystack DocumentStore with Full Text Search
-- This script creates the necessary tables and indexes for Haystack to use PostgreSQL FTS
-- Execute this script after deploying the infrastructure via Terraform

-- Enable necessary extensions (if not already enabled)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Documents table with Full Text Search support
-- This schema is compatible with Haystack's SQLDocumentStore requirements
-- and provides Supabase-compatible PostgreSQL FTS semantics
CREATE TABLE IF NOT EXISTS documents (
  -- Unique identifier for each document
  id TEXT PRIMARY KEY,
  
  -- Document content - full text that will be indexed
  content TEXT NOT NULL,
  
  -- Content type indicator (e.g., 'text', 'html', 'markdown')
  content_type TEXT DEFAULT 'text',
  
  -- Metadata stored as JSONB for flexible filtering and querying
  meta JSONB DEFAULT '{}',
  
  -- Relevance score (populated by retrieval operations)
  score FLOAT DEFAULT NULL,
  
  -- Optional: Embedding vector for hybrid search (not used in minimal FTS setup)
  embedding FLOAT[] DEFAULT NULL,
  
  -- Full text search vector - automatically generated from content
  -- GENERATED ALWAYS ensures tsvector stays in sync with content
  -- Uses 'english' text search configuration for stemming and stop words
  content_tsv tsvector GENERATED ALWAYS AS (to_tsvector('english', coalesce(content, ''))) STORED,
  
  -- Timestamps for tracking
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- GIN index for full text search performance
-- GIN (Generalized Inverted Index) is optimal for tsvector columns
-- This enables fast searching using @@ operator and ts_rank functions
CREATE INDEX IF NOT EXISTS documents_content_tsv_idx 
  ON documents 
  USING GIN(content_tsv);

-- GIN index on metadata for efficient filtering
-- Allows fast queries on JSONB fields using @>, ?, and other operators
CREATE INDEX IF NOT EXISTS documents_meta_idx 
  ON documents 
  USING GIN(meta);

-- B-tree index on id for fast primary key lookups
CREATE INDEX IF NOT EXISTS documents_id_idx 
  ON documents(id);

-- B-tree index on content_type for filtering by document type
CREATE INDEX IF NOT EXISTS documents_content_type_idx 
  ON documents(content_type);

-- Trigger to update updated_at timestamp on row modification
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_documents_updated_at 
  BEFORE UPDATE ON documents
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Example queries for testing FTS functionality:

-- Simple FTS query using plainto_tsquery
-- SELECT id, content, ts_rank(content_tsv, plainto_tsquery('english', 'search term')) AS rank
-- FROM documents
-- WHERE content_tsv @@ plainto_tsquery('english', 'search term')
-- ORDER BY rank DESC
-- LIMIT 10;

-- Advanced FTS query with metadata filtering
-- SELECT id, content, meta, ts_rank_cd(content_tsv, to_tsquery('english', 'search & term')) AS rank
-- FROM documents
-- WHERE content_tsv @@ to_tsquery('english', 'search & term')
--   AND meta @> '{"category": "technical"}'::jsonb
-- ORDER BY rank DESC
-- LIMIT 10;

-- Phrase search using phraseto_tsquery
-- SELECT id, content, ts_rank(content_tsv, phraseto_tsquery('english', 'exact phrase')) AS rank
-- FROM documents
-- WHERE content_tsv @@ phraseto_tsquery('english', 'exact phrase')
-- ORDER BY rank DESC;

COMMENT ON TABLE documents IS 'Haystack DocumentStore table with PostgreSQL Full Text Search support';
COMMENT ON COLUMN documents.content_tsv IS 'Full text search vector automatically generated from content using English stemming';
COMMENT ON INDEX documents_content_tsv_idx IS 'GIN index for fast full text search using tsvector and tsquery';
