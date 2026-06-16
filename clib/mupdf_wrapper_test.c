#include "mupdf/include/mupdf/fitz.h"
#include <string.h>
#include <stdio.h>
#include <stdarg.h>
#include <stdbool.h>

static fz_document *doc = NULL;
static fz_context *ctx = NULL;

// ----------------------------- Error Handling ---------------------------
static void my_error(void *user, const char *message)
{
    fprintf(stderr, "MuPDF error: %s\n", message);
}

static void extract_page_images(fz_document *doc, int page_number, const char *outdir)
{
    fz_page *page = NULL;
    fz_stext_page *stext = NULL;
    fz_device *dev = NULL;

    fz_try(ctx)
    {
        page = fz_load_page(ctx, doc, page_number - 1);
        if (!page)
            fz_throw(ctx, FZ_ERROR_GENERIC, "cannot load page %d", page_number);

        fz_rect mediabox = fz_bound_page(ctx, page);
        stext = fz_new_stext_page(ctx, mediabox);

        fz_stext_options opts = {0};
        opts.flags = FZ_STEXT_PRESERVE_IMAGES;

        dev = fz_new_stext_device(ctx, stext, &opts);
        fz_run_page(ctx, page, dev, fz_identity, NULL);
        fz_close_device(ctx, dev);

        int img_index = 1;
        for (fz_stext_block *block = stext->first_block; block; block = block->next)
        {
            if (block->type == FZ_STEXT_BLOCK_IMAGE)
            {
                fz_image *img = block->u.i.image;
                fz_pixmap *pix = fz_get_pixmap_from_image(ctx, img, NULL, NULL, 0, 0);

                char namebuf[128];
                fz_snprintf(namebuf, sizeof(namebuf),
                            "page-%03d-img-%03d", page_number, img_index++);

                char pathbuf[1024];
                fz_snprintf(pathbuf, sizeof(pathbuf), "%s/%s.png", outdir, namebuf);

                fz_save_pixmap_as_png(ctx, pix, pathbuf);
                fz_drop_pixmap(ctx, pix);
            }
        }
    }
    fz_always(ctx)
    {
        if (dev) fz_drop_device(ctx, dev);
        if (stext) fz_drop_stext_page(ctx, stext);
        if (page) fz_drop_page(ctx, page);
    }
    fz_catch(ctx)
    {
        fz_warn(ctx, "failed to extract images from page %d", page_number);
    }
}


static void extract_range(fz_document *doc, const char *range, const char *outdir)
{
    int spage, epage, pagecount = fz_count_pages(ctx, doc);
    int page;

    while ((range = fz_parse_page_range(ctx, range, &spage, &epage, pagecount)))
    {
        if (spage <= epage)
        {
            for (page = spage; page <= epage; page++)
                extract_page_images(doc, page, outdir);
        }
        else
        {
            for (page = spage; page >= epage; page--)
                extract_page_images(doc, page, outdir);
        }
    }

}
static int usage(void)
{
    fprintf(stderr, "usage: mutool image [options] file.pdf [pages]\n");
    fprintf(stderr, "\t-p <password>\n");
    fprintf(stderr, "\t-o <dir> output directory (default .)\n");
    fprintf(stderr, "\tpages\tcomma separated list of page numbers and ranges\n");
    return 1;
}

int main(int argc, char **argv)
{
    char *filename;
    char *password = "";
    char *outdir = ".";
    int c;

    ctx = fz_new_context(NULL, NULL, FZ_STORE_UNLIMITED);
    if (!ctx) {
        fprintf(stderr, "cannot initialise context\n");
        return EXIT_FAILURE;
    }

    while ((c = fz_getopt(argc, argv, "p:o:")) != -1)
    {
        switch (c)
        {
        case 'p': password = fz_optarg; break;
        case 'o': outdir = fz_optarg; break;
        default: return usage();
        }
    }

    if (fz_optind == argc)
        return usage();

    filename = argv[fz_optind++];

    fz_try(ctx) {
        fz_mkdir(outdir);
    }
    fz_catch(ctx) {
        fz_warn(ctx, "Failed to create output dir: %s", outdir);
    }

    ctx = fz_new_context(NULL, NULL, FZ_STORE_UNLIMITED);
    if (!ctx) {
        fprintf(stderr, "Cannot create MuPDF context\n");
        return EXIT_FAILURE;
    }

    fz_set_error_callback(ctx, my_error, NULL);
    fz_register_document_handlers(ctx);

    fz_try(ctx)
    {
        doc = fz_open_document(ctx, filename);
        if (fz_needs_password(ctx, doc))
            if (!fz_authenticate_password(ctx, doc, password))
                fz_throw(ctx, FZ_ERROR_GENERIC, "cannot authenticate password");

        if (fz_optind == argc || !fz_is_page_range(ctx, argv[fz_optind]))
            extract_range(doc, "1-N", outdir);
        if (fz_optind < argc && fz_is_page_range(ctx, argv[fz_optind]))
            extract_range(doc, argv[fz_optind++], outdir);

    }
    fz_always(ctx)
    {
        fz_drop_document(ctx, doc);
    }
    fz_catch(ctx)
    {
        fz_report_error(ctx);
        return EXIT_FAILURE;
    }

    fz_drop_context(ctx);
    return EXIT_SUCCESS;
}