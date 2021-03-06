assert_no_unclosed_tokens <- function(tokens_matches, txt_line_md) {
  if (!all(table(tokens_matches) %% 2 == 0)) {
    stop(
      "It looks like you have some unclosed markdown tokens in a line.",
      " See matches (and order) below:\n",
      paste(tokens_matches, collapse = ", "),
      "\nIn line: ",
      txt_line_md
    )
  }
}


assert_no_nested_tokens <- function(tokens_matches, txt_line_md) {
  if (!all((rle(tokens_matches)$lengths %% 2) == 0)) {
    stop(
      "It looks like you have some nested markdown tokens in a line.",
      " See matches (and order) below:\n",
      paste(tokens_matches, collapse = ", "),
      "\nIn line: ",
      txt_line_md
    )
  }
}


parse_token_syntax <- function(txt_line_md, patterns) {
  rgxs_to_search <- purrr::map_chr(patterns, "rgx")
  grouped_rgx <- stringi::stri_c("(", rgxs_to_search, ")") %>%
    stringi::stri_c(collapse = "|")

  tokens_matrix <-
    stringi::stri_match_all_regex(txt_line_md, grouped_rgx)[[1]]
  tokens_matches <- tokens_matrix[, 1]
  if (all(is.na(tokens_matches))) {
    return(character(0))
  }
  assert_no_unclosed_tokens(tokens_matches, txt_line_md)
  assert_no_nested_tokens(tokens_matches, txt_line_md)

  last_non_na_col_per_row <-
    apply(tokens_matrix, 1, function(x)
      max(which(!is.na(x))))
  last_non_na_col_per_row_dedup <-
    last_non_na_col_per_row[seq(1, length(last_non_na_col_per_row), 2)]
  content_of_matches <-
    stringi::stri_split_regex(txt_line_md, grouped_rgx)[[1]]

  non_plain <- tibble::tibble(name = names(rgxs_to_search)[last_non_na_col_per_row_dedup - 1])

  plain <- tibble::tibble(name = rep("plain", nrow(non_plain) + 1))


  dplyr::bind_rows(
    dplyr::mutate(plain, row_n = dplyr::row_number()),
    dplyr::mutate(non_plain, row_n = dplyr::row_number()),
    .id = "src_id"
  ) %>%
    dplyr::arrange(row_n, src_id) %>%
    dplyr::bind_cols(content = content_of_matches) %>%
    dplyr::select(-src_id, -row_n)
}


sym_to_fun <- function(txt_line_md, patterns) {
  token_to_search <- parse_token_syntax(txt_line_md, patterns)

  txt_line_fun <- paste0("plain(", txt_line_md, ")")
  if (length(token_to_search) == 0)
    return(txt_line_fun)

  patterns_tib <-
    tibble::enframe(patterns) %>% tidyr::unnest_wider(value)
  token_to_search %>%
    dplyr::left_join(patterns_tib, by = "name") %>%
    dplyr::mutate(
      fun = dplyr::if_else(name == "plain", "plain", fun),
      color = dplyr::if_else(name == "plain", "medgrey", color),
      wrapped_content = purrr::map2_chr(fun, content, ~ paste0(.x, "('", .y, "')"))
    )
}


rep_sym_w_fun <- function(sentence, pattern) {
  md_positions <- stringr::str_locate_all(sentence, pattern$rgx)[[1]]

  if (nrow(md_positions) > 0) {
    for (i in 1:(nrow(md_positions) / 2)) {
      md_positions <- stringr::str_locate_all(sentence, pattern$rgx)[[1]]
      stringr::str_sub(sentence, md_positions[1, 1], md_positions[1, 2]) <-
        paste0(pattern$fun, "∆")
      shift_pos <- nchar(pattern$fun) + 1 - nchar(pattern$md)
      stringr::str_sub(sentence,
                       md_positions[2, 1] + shift_pos,
                       md_positions[2, 2] + shift_pos) <- "∆"
    }
  }

  sentence
}


text_colors <- list(
  darkblue = list(red = 6, green = 58, blue = 109),
  medgrey = list(red = 76, green = 76, blue = 76)
)


md_to_exp <- function(sentence) {
  md_bold <- list(
    md = "**",
    rgx = "\\*\\*",
    fun = "bold",
    color = list(
      red = 76,
      green = 76,
      blue = 76
    )
  )
  md_italic <- list(
    md = "*",
    rgx = "\\*",
    fun = "italic",
    color = list(
      red = 76,
      green = 76,
      blue = 76
    )
  )
  md_code <- list(
    md = "`",
    rgx = "`",
    fun = "bolditalic",
    color = list(
      red = 6,
      green = 58,
      blue = 109
    )
  )

  sentence %>%
    rep_sym_w_fun(md_bold) %>%
    rep_sym_w_fun(md_italic) %>%
    rep_sym_w_fun(md_code) %>%
    stringr::str_replace_all("bold∆(.*?)∆", "', bold('\\1\'),'") %>%
    stringr::str_replace_all("bolditalic∆(.*?)∆", "', bolditalic('\\1\'),'") %>%
    stringr::str_replace_all("(?<!bold)italic∆(.*?)∆", "', italic('\\1\'),'") %>% {
      stringr::str_glue("expression(paste('{.}'))")
    }
}

#' Title
#'
#' @param slide
#' @param input_text
#' @param x_pos
#' @param y_pos
#' @param adj
#' @param cex
#' @param alpha
#' @param prose_family
#' @param prose_color
#' @param code_color
#'
#' @return
#' @export
#'
#' @examples
write_on_slide <-
  function(slide,
           input_text,
           x_pos,
           y_pos,
           adj,
           cex,
           alpha,
           prose_family,
           prose_color = rgb(76, 76, 76, alpha = alpha * 255, maxColorValue = 255),
           code_color = rgb(6, 58, 109, alpha = alpha * 255, maxColorValue = 255)) {

    slide <- magick::image_draw(slide)

    showtext::showtext_begin()

    exp_label <- md_to_exp(input_text)
    exp_label_non_code <- stringr::str_replace_all(exp_label,
                                                   "bolditalic\\(.*?\\)",
                                                   "phantom(\\0)")

    graphics::text(
      x = x_pos,
      y = y_pos,
      labels = eval(parse(text = exp_label)),
      col = ifelse(alpha == 1, code_color, prose_color),
      family = prose_family,
      cex = cex,
      adj = adj
    )

    if (alpha == 1) {
      graphics::text(
        x = x_pos,
        y = y_pos,
        labels = eval(parse(text = exp_label_non_code)),
        col = prose_color,
        family = prose_family,
        cex = cex,
        adj = adj
      )
    }

    showtext::showtext_end()
    grDevices::dev.off()
    slide
  }

caption_template <-
  function(slide,
           caption,
           x_pos,
           y_pos) {
    write_on_slide(
      slide,
      input_text = caption,
      x_pos = x_pos,
      y_pos = y_pos,
      adj = 0.5,
      cex = 3.7,
      alpha = 1,
      prose_family = "helveticaneue"
    )
  }